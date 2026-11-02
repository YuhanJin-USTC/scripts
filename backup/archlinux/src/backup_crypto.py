"""Own the private GPG runtime independently of decrypted backup payloads."""

import argparse
import errno
import json
import os
from pathlib import Path
import re
import select
import socket
import stat
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from backup_set import cleanup_owned, regular_parents, temp_identity

SOCKETS = {'S.gpg-agent', 'S.gpg-agent.ssh', 'S.gpg-agent.extra', 'S.gpg-agent.browser'}


def private_dir(path, expected=None):
    regular_parents(path)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o700 or info.st_uid != os.geteuid():
        raise ValueError(f'Expected an owned private directory: {path}')
    identity = temp_identity(path)
    if expected is not None and identity != expected:
        raise ValueError(f'Private directory was replaced: {path}')
    return identity


def record(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_size > 1024 * 1024:
        raise ValueError(f'Invalid recovery record: {path}')
    return json.loads(path.read_bytes())


def runtime_parent():
    return Path('/run/user') / str(os.geteuid()) / 'gnupg'


def before_sockets():
    parent = runtime_parent()
    regular_parents(parent)
    existed = parent.exists()
    if existed:
        private_dir(parent)
    return {'parent': str(parent), 'existed': existed,
            'identity': [parent.stat().st_dev, parent.stat().st_ino] if existed else None,
            'children': [p.name for p in parent.iterdir()] if existed else []}


def routes(home):
    def get(name):
        value = subprocess.check_output(['gpgconf', '--homedir', str(home), '--list-dirs', name],
                                        text=True, timeout=10).strip()
        path = Path(value)
        if not path.is_absolute() or '..' in path.parts:
            raise ValueError('Invalid private GPG socket route.')
        return path
    directory, agent = get('socketdir'), get('agent-socket')
    if agent != directory / 'S.gpg-agent':
        raise ValueError('Private GPG agent socket route differs.')
    return directory


def external_directory(directory, before):
    parent = runtime_parent()
    if (before.get('parent') != str(parent) or directory.parent != parent or
            not re.fullmatch(r'd\.[A-Za-z0-9]+', directory.name) or directory.name in before['children']):
        raise ValueError('Refusing to use a shared or pre-existing GPG socket directory.')
    private_dir(parent)
    actual = [parent.stat().st_dev, parent.stat().st_ino]
    expected = before['identity'] if before['existed'] else before.get('created_parent_identity')
    if expected is not None and actual != expected:
        raise ValueError('GPG runtime parent was replaced.')
    return actual


def start():
    root = Path(tempfile.mkdtemp(prefix='arch-crypto.', dir='/tmp'))
    home = root / 'gpg-home'
    identity = private_dir(root)
    owned_socket = None
    try:
        home.mkdir(mode=0o700)
        before = before_sockets()
        directory = routes(home)
        if directory != home:
            parent_id = external_directory(directory, before)
            if not before['existed']:
                before['created_parent_identity'] = parent_id
            private_dir(directory)
            if any(directory.iterdir()):
                raise ValueError('Expected an empty invocation-owned socket directory.')
            owned_socket = (directory, before, private_dir(directory))
        state = {'home_id': private_dir(home), 'directory': str(directory),
                 'directory_id': private_dir(directory), 'before': before}
        (root / 'crypto-state.json').write_text(json.dumps(state), encoding='utf-8')
        print(f'{root}\t{identity}', flush=True)
    except BaseException:
        # No encryption command has been launched yet.
        os.environ['CODEX_TEMP_CLEANUP'] = '1'
        if owned_socket:
            close_sockets(home, *owned_socket)
        cleanup_owned(root, identity)
        raise


def uses_home(process, home):
    args = (process / 'cmdline').read_bytes().split(b'\0')
    for i, arg in enumerate(args):
        if arg == b'--homedir':
            return args[i + 1:i + 2] == [os.fsencode(home)]
        if arg.startswith(b'--homedir='):
            return arg[10:] == os.fsencode(home)
    return False  # These private agents are launched with an explicit --homedir.


def agent_process(process):
    try:
        return os.readlink(process / 'exe').removesuffix(' (deleted)') == os.path.realpath('/usr/bin/gpg-agent')
    except PermissionError:
        # A non-dumpable agent can hide /proc/PID/exe even from its owner.
        argv0 = (process / 'cmdline').read_bytes().split(b'\0', 1)[0]
        return (process / 'comm').read_text().strip() == 'gpg-agent' and os.path.basename(argv0) == b'gpg-agent'


def effective_uid(process):
    for line in (process / 'status').read_text().splitlines():
        if line.startswith('Uid:'):
            return int(line.split()[2])
    raise ValueError('Missing agent process identity.')


def matching_process(home):
    for process in Path('/proc').iterdir():
        if not process.name.isdecimal():
            continue
        try:
            if (process / 'comm').read_text().strip() != 'gpg-agent' or effective_uid(process) != os.geteuid():
                continue
            if agent_process(process) and uses_home(process, home):
                return True
        except (FileNotFoundError, ProcessLookupError):
            continue
    return False


def stop_agent(directory, home):
    path = directory / 'S.gpg-agent'
    if path.exists() or path.is_symlink():
        info = path.lstat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.geteuid():
            raise ValueError('Unsafe private agent endpoint.')
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(3)
            try:
                client.connect(str(path))
            except (ConnectionRefusedError, FileNotFoundError):
                pass
            else:
                peer, uid, _ = struct.unpack('3i', client.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
                if uid != os.geteuid():
                    raise ValueError('Unexpected private agent peer UID.')
                with client.makefile('rb') as protocol:
                    if protocol.readline(4096).split()[:1] != [b'OK']:
                        raise ValueError('Unexpected private agent greeting.')
                    # A daemon can inherit a listener from a parent that has exited.
                    client.sendall(b'GETINFO pid\n')
                    reported = []
                    for _ in range(16):
                        line = protocol.readline(4096).strip()
                        if line.split()[:1] in ([b'OK'], [b'ERR']):
                            break
                        match = re.fullmatch(rb'D ([1-9][0-9]*)', line)
                        if match:
                            reported.append(int(match[1]))
                    else:
                        raise ValueError('Incomplete private agent response.')
                    if len(reported) > 1:
                        raise ValueError('Ambiguous private agent PID.')
                    pid = reported[0] if reported and line.split()[:1] == [b'OK'] else peer
                    client.sendall(b'GETINFO socket_name\n')
                    socket_name = protocol.readline(4096).rstrip(b'\r\n')
                    if socket_name != b'D ' + os.fsencode(path) or protocol.readline(4096).split()[:1] != [b'OK']:
                        raise ValueError('Private agent did not confirm its socket name.')
                    proc = Path('/proc') / str(pid)
                    fd = os.pidfd_open(pid)
                    try:
                        if effective_uid(proc) != uid or not agent_process(proc) or not uses_home(proc, home):
                            raise ValueError('Could not establish ownership of the private GPG agent.')
                        client.sendall(b'KILLAGENT\n')
                        reply = protocol.readline(4096)
                        if reply and reply.split()[:1] != [b'OK']:
                            raise ValueError('Private agent declined shutdown.')
                    except BaseException:
                        os.close(fd)
                        raise
                client.close()
                try:
                    poll = select.poll()
                    poll.register(fd, select.POLLIN)
                    if not poll.poll(4000):
                        raise ValueError('Private GPG agent has not exited.')
                finally:
                    os.close(fd)
    if matching_process(home):
        raise ValueError('A private agent is still running for this homedir.')


def close_sockets(home, directory, before, expected):
    external = directory != home
    if external:
        if directory.exists() or directory.is_symlink():
            external_directory(directory, before)
    if directory.exists() or directory.is_symlink():
        private_dir(directory, expected)
    stop_agent(directory, home)
    if directory.exists():
        for path in list(directory.iterdir()):
            info = path.lstat()
            if path.name not in SOCKETS:
                if external or stat.S_ISSOCK(info.st_mode):
                    raise ValueError(f'Unexpected entry in private socket directory: {path.name}')
                continue
            if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.geteuid():
                raise ValueError('Unexpected object at private socket path.')
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as probe:
                probe.settimeout(1)
                if probe.connect_ex(str(path)) not in (errno.ECONNREFUSED, errno.ENOENT):
                    raise ValueError('A private socket still has a listener.')
            if path.exists() and os.path.samestat(info, path.lstat()):
                path.unlink()
        if external:
            private_dir(directory, expected)
            directory.rmdir()
    parent = runtime_parent()
    if external and before.get('created_parent_identity') and parent.exists():
        external_directory(directory, before)
        try:
            parent.rmdir()
        except OSError as error:
            if error.errno != errno.ENOTEMPTY:
                raise


def owned_cleanup(root, identity, legacy=False):
    if os.environ.get('CODEX_TEMP_CLEANUP') != '1':
        raise ValueError('Cleanup requires CODEX_TEMP_CLEANUP=1.')
    private_dir(root, identity)
    home = root / 'gpg-home'
    if legacy:
        private_dir(home)
        before = record(root / 'gpg-socket-before.json')
        directory = routes(home)
        if directory != home:
            external_directory(directory, before)
        expected = private_dir(directory)
        receipt = root / 'crypto-runtime.json'
        if receipt.exists():
            old = record(receipt)
            if old['home'] != str(home) or old['socket_directory'] != str(directory):
                raise ValueError('Recorded private GPG routes differ.')
            private_dir(home, old['home_identity'])
            if directory != home:
                private_dir(directory, old['socket_identity'])
    else:
        state = record(root / 'crypto-state.json')
        private_dir(home, state['home_id'])
        directory, before, expected = Path(state['directory']), state['before'], state['directory_id']
        if directory != home and (directory.parent != runtime_parent() or not re.fullmatch(r'd\.[A-Za-z0-9]+', directory.name)):
            raise ValueError('Invalid recorded socket directory.')
    close_sockets(home, directory, before, expected)
    cleanup_owned(root, identity)


def retained(root, expected, execute):
    legacy = re.fullmatch(r'arch-restore-payload\.[a-zA-Z0-9_]{8}', root.name) is not None
    if root.parent != Path('/tmp') or not (legacy or re.fullmatch(r'arch-crypto\.[a-zA-Z0-9_]{8}', root.name)):
        raise ValueError('Expected the exact private directory printed in the failed operation.')
    if not root.exists() and not root.is_symlink():
        print(json.dumps({'status': 'absent', 'path': str(root)}))
        return
    identity = private_dir(root)
    home_id = private_dir(root / 'gpg-home')
    if legacy:
        manifest = record(root / 'set.json')
        if manifest.get('state') != 'COMPLETE' or not re.fullmatch(r'[0-9]{8}T[0-9]{6}Z-[a-f0-9]{12}', manifest.get('id', '')):
            raise ValueError('Missing previous restore identity.')
        if record(root / 'gpg-socket-before.json').get('parent') != str(runtime_parent()):
            raise ValueError('Missing previous private runtime record.')
    else:
        if record(root / 'crypto-state.json')['home_id'] != home_id:
            raise ValueError('GPG home was replaced.')
    token = f'{identity}/{home_id}'
    if execute:
        if expected != token or not expected:
            raise ValueError('Root/home identities differ from preview.')
        for p in Path('/proc').iterdir():
            if not p.name.isdecimal():
                continue
            try:
                if p.stat().st_uid != os.geteuid() or (p/'comm').read_text().strip() not in ('bash', 'sh'):
                    continue
                if any(a.rsplit(b'/', 1)[-1] in (b'backup.sh', b'restore.sh') for a in (p/'cmdline').read_bytes().split(b'\0')):
                    raise ValueError('Finish the running backup or restore before retained cleanup.')
            except (FileNotFoundError, ProcessLookupError):
                continue
        for line in Path('/proc/self/mountinfo').read_text().splitlines():
            mount = Path(line.split()[4])
            if mount.is_relative_to(root):
                raise ValueError('Retained directory contains a mount; refusing cleanup.')
        private_dir(root / 'gpg-home', home_id)
        owned_cleanup(root, identity, legacy)
    print(json.dumps({'status': 'removed' if execute else 'preview', 'path': str(root), 'identity': token}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    cmds = parser.add_subparsers(dest='command', required=True)
    cmds.add_parser('start')
    cmd = cmds.add_parser('close')
    cmd.add_argument('path', type=Path); cmd.add_argument('identity')
    cmd = cmds.add_parser('retained')
    cmd.add_argument('path', type=Path); cmd.add_argument('--expect-identity'); cmd.add_argument('--run', action='store_true')
    args = parser.parse_args()
    if args.command == 'start':
        start()
    elif args.command == 'close':
        if args.path.parent != Path('/tmp') or not re.fullmatch(r'arch-crypto\.[a-zA-Z0-9_]{8}', args.path.name):
            raise ValueError('Unexpected private crypto root.')
        owned_cleanup(args.path, args.identity)
    else:
        retained(args.path, args.expect_identity, args.run)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'[ERROR] {error}', file=sys.stderr)
        raise SystemExit(1)
