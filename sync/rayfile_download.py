#!/usr/bin/env python3

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import selectors
import select
import signal
import shlex
import time
import termios
import shutil
import subprocess
import stat
import sys
import uuid


HOSTS = {
    "hfcluster": ("hefei03.nscc-hf.cn", 65012),
    "tycluster": ("tycs1.hpccube.com", 65112),
    "wzcluster": ("wuzh01.hpccube.com", 65012),
}
SSH_ROOTS = {
    "hfcluster": "/public/home/yuhanjin",
    "tycluster": "/work/home/yuhanjin",
    "wzcluster": "/work/home/yuhanjin",
}
CLIENT_SHA256 = "f718db7def476df9cdb259e0424b54bb0d0f82ed864adb84c62730b73d01b0a7"
MAX_RESPONSE = 1024 * 1024
CONTROL = re.compile(r"[\x00-\x1f\x7f]")

# Metadata only; opening directories never follows links.
SSH_INVENTORY = r'''
import json, os, stat, sys
root = sys.argv[1]
records = []
flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
def walk(fd, prefix):
    for name in sorted(os.listdir(fd)):
        path = prefix + name
        item = os.stat(name, dir_fd=fd, follow_symlinks=False)
        kind = "file" if stat.S_ISREG(item.st_mode) else "directory" if stat.S_ISDIR(item.st_mode) else "link" if stat.S_ISLNK(item.st_mode) else "unknown"
        records.append({"path": path, "type": kind, "size": item.st_size,
                        "mtime_ns": item.st_mtime_ns, "inode": item.st_ino, "device": item.st_dev})
        if len(records) > 10000:
            raise ValueError("Inventory exceeds 10000 entries")
        if kind == "directory":
            child = os.open(name, flags, dir_fd=fd)
            try:
                current = os.fstat(child)
                if (current.st_ino, current.st_dev) != (item.st_ino, item.st_dev):
                    raise ValueError("Directory changed during inventory")
                walk(child, path + "/")
            finally:
                os.close(child)
fd = os.open("/", flags)
try:
    for part in root.split("/")[1:]:
        child = os.open(part, flags, dir_fd=fd)
        os.close(fd)
        fd = child
    walk(fd, "")
finally:
    os.close(fd)
result = json.dumps({"schema": 1, "source": root, "entries": records}, ensure_ascii=True)
if len(result.encode("utf-8")) > 1048576:
    raise ValueError("Inventory exceeds 1 MiB")
print(result)
'''


def ssh_source(target, source):
    validate_source(source)
    return SSH_ROOTS[target] + source


def ssh_command(target, script, *arguments):
    command = shlex.join(["python3", "-B", "-c", script, *arguments])
    return ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
            "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2", "-T", target, command]


def ssh_inventory(target, source):
    if not shutil.which("ssh"):
        raise ValueError("SSH is required for the explicit SSH metadata mode.")
    root = ssh_source(target, source)
    env = os.environ.copy()
    env.pop("RAYFILE_TOKEN", None)
    code, response = read_response(ssh_command(target, SSH_INVENTORY, root), env,
                                   label="SSH inventory")
    if code:
        detail = response.decode("utf-8", errors="replace")[:2048]
        detail = "".join(c if c in "\n\t" or ord(c) >= 32 and ord(c) != 127 else repr(c)[1:-1] for c in detail).strip()
        raise ValueError(f"SSH inventory failed (exit {code}); verify the existing SSH alias, known host and batch authentication locally.\n{detail}")
    try:
        result = json.loads(response)
    except (UnicodeError, ValueError):
        raise ValueError("SSH inventory did not return complete structured metadata.") from None
    if not isinstance(result, dict) or result.get("schema") != 1 or result.get("source") != root or not isinstance(result.get("entries"), list):
        raise ValueError("SSH inventory has an unexpected schema or source.")
    entries = result["entries"]
    for entry in entries:
        if not isinstance(entry, dict) or any(type(entry.get(field)) is not int or entry[field] < 0 for field in ("size", "mtime_ns", "inode", "device")):
            raise ValueError("SSH inventory has invalid stat metadata.")
    selected_entries(entries)
    return entries


def inspect_ssh(args):
    entries = ssh_inventory(args.target, args.source)
    chosen = selected_entries(entries, args.prefix, args.suffix)
    print(f"SSH source: {args.target}:{ssh_source(args.target, args.source)}")
    print(f"Inventory: {len(entries)} entries; selected: {len(chosen)}")
    for item in chosen:
        print(f"{item['type']}\t{item['size']}\t{item['path']}")
    print("[OK] SSH metadata selection completed; no token, payload read or download.")
    return 0


def filename_pattern(prefix, suffix):
    for part in (prefix, suffix):
        if CONTROL.search(part) or "/" in part or "\\" in part or "**" in part or "[:" in part:
            raise ValueError("Only filename glob *, ? and [] are supported; /, \\, ** and POSIX classes are refused.")
    pattern = prefix + "*" + suffix
    if "**" in pattern and (prefix or suffix):
        raise ValueError("The combined prefix*suffix must not contain **.")
    normalized = []
    index = 0
    while index < len(pattern):
        if pattern[index] != "[":
            normalized.append(pattern[index])
            index += 1
            continue
        closing = index + 1
        if closing < len(pattern) and pattern[closing] in "!^":
            closing += 1
        if closing < len(pattern) and pattern[closing] == "]":
            closing += 1
        closing = pattern.find("]", closing)
        if closing == -1:
            raise ValueError("Filename glob character classes must have a closing ].")
        group = pattern[index:closing + 1]
        normalized.append("[!" + group[2:] if group.startswith("[^") else group)
        index = closing + 1
    return "".join(normalized)


def safe_relative(value):
    if not isinstance(value, str) or not value or CONTROL.search(value) or "\\" in value:
        raise ValueError("Unsafe listing path.")
    if value.startswith("/") or any(p in ("", ".", "..") for p in value.split("/")):
        raise ValueError("Listing path must stay below the selected source.")
    return PurePosixPath(value)


def selected_entries(entries, prefix="", suffix=""):
    # This consumes verified metadata, never guessed native output.
    pattern = filename_pattern(prefix, suffix)
    records = {}
    for entry in entries:
        path = safe_relative(entry.get("path"))
        if entry.get("type") not in ("file", "directory"):
            raise ValueError(f"Link or unknown entry type: {path}")
        if path in records:
            raise ValueError(f"Duplicate listing path: {path}")
        records[path] = entry
    for path in records:
        for parent in path.parents:
            if str(parent) != "." and records.get(parent, {}).get("type") != "directory":
                raise ValueError(f"Missing directory metadata: {parent}")
    if not prefix and not suffix:
        return list(records.values())
    # rsync wildmatch works on filename bytes.
    wildcard = pattern.encode("utf-8")
    return [entry for path, entry in records.items()
            if all(fnmatch.fnmatchcase(part.encode("utf-8"), wildcard) for part in path.parts)]


def validate_source(value):
    if not value.startswith("/"):
        raise ValueError("Use an absolute portal source path.")
    safe_relative(value.removeprefix("/"))


def redact(text, token):
    text = text.replace(token, "<hidden>") if token else text
    return re.sub(r"(?i)((?:password|token)\s*[:=]\s*)\S+", r"\1<hidden>", text)


def probe_command(client, home, target, source, token, operation):
    if operation not in ("list", "attributes"):
        raise ValueError("Only read-only metadata probes are supported.")
    address, port = HOSTS[target]
    paths = ["-s", source, "-d", source] if operation == "attributes" else ["-d", source]
    return ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
            "--tmpfs", "/tmp", "--ro-bind", str(client), "/tmp/rayfile-c",
            "--tmpfs", str(home), "--chdir", "/tmp", "--", "/tmp/rayfile-c",
            "-a", address, "-P", str(port), "-u", "yuhanjin", "-o", operation,
            *paths, "-retry", "1", "-retrytimeout", "10", "-w", token]


def download_command(client, home, target, source, stage, token, filelist=None):
    address, port = HOSTS[target]
    paths = ["-s", source]
    mounts = []
    if filelist is not None:
        mounts = ["--ro-bind", str(filelist), "/tmp/source-list"]
        paths = ["-fl", "/tmp/source-list"]
    return ["bwrap", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc",
            "--tmpfs", "/tmp", "--ro-bind", str(client), "/tmp/rayfile-c",
            "--tmpfs", str(home), "--bind", str(stage), "/tmp/rayfile-stage", *mounts,
            "--chdir", "/tmp", "--", "/tmp/rayfile-c",
            "-a", address, "-P", str(port), "-u", "yuhanjin", "-o", "download",
            *paths, "-d", "/tmp/rayfile-stage", "-no-meta", "-symbolic-links", "copy_force",
            "-file-update", "rename", "-retry", "1", "-retrytimeout", "10", "-w", token]


def read_token():
    token = os.environ.get("RAYFILE_TOKEN", "")
    if token:
        return token
    if not sys.stdin.isatty():
        raise ValueError("Run this operation in a local terminal for hidden token input, or set RAYFILE_TOKEN there.")
    descriptor = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
    previous = termios.tcgetattr(descriptor)
    hidden = list(previous)
    hidden[6] = list(previous[6])
    hidden[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON)
    hidden[6][termios.VMIN] = 1
    hidden[6][termios.VTIME] = 0
    value = bytearray()
    start, end = b"\x1b[200~", b"\x1b[201~"
    try:
        termios.tcsetattr(descriptor, termios.TCSAFLUSH, hidden)
        os.write(descriptor, b"\x1b[?2004hPaste is supported. Input is hidden (no echo); paste one line, then press Enter.\nFast-transfer token: ")
        complete = False
        while not complete:
            chunk = os.read(descriptor, 65536)
            if not chunk:
                raise ValueError("Token input cancelled.")
            for index, byte in enumerate(chunk):
                in_paste = value.startswith(start) and end not in value
                if byte in (10, 13) and not in_paste:
                    if index + 1 != len(chunk):
                        raise ValueError("Paste one token line only; extra input was discarded.")
                    complete = True
                    break
                if byte == 4:
                    raise ValueError("Token input cancelled.")
                if not in_paste and byte in (8, 127):
                    if value: value.pop()
                elif not in_paste and byte == 21:
                    value.clear()
                else:
                    value.append(byte)
                if len(value) > MAX_RESPONSE:
                    raise ValueError("Token input exceeded the 1 MiB limit.")
        if value.startswith(start) and value.endswith(end):
            value = value[len(start):-len(end)]
        if select.select([descriptor], [], [], 0.05)[0]:
            raise ValueError('Extra token input was discarded; paste one line only.')
        token = value.decode('utf-8')
        if not token.strip() or CONTROL.search(token):
            raise ValueError('A non-empty single-line token without control characters is required.')
    finally:
        termios.tcsetattr(descriptor, termios.TCSAFLUSH, previous)
        os.write(descriptor, b"\x1b[?2004l\n")
        os.close(descriptor)
    print("Token received (hidden).", file=sys.stderr)
    return token


def native_probe_failed(code, output):
    return code != 0 or bool(re.search(
        r"Unknown param|please check operation|Error:|(?:server|source|destination) path(?: or local path)? is empty\.|^\s*Usage:",
        output, re.I | re.M))


def read_response(command, env, timeout=45, limit=MAX_RESPONSE, label="Rayfile metadata probe"):
    output = bytearray()
    deadline = time.monotonic() + timeout
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env=env, start_new_session=True) as process:
        try:
            with selectors.DefaultSelector() as ready:
                ready.register(process.stdout, selectors.EVENT_READ)
                while ready.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                        raise ValueError(f"{label} timed out; operation stopped.")
                    for key, _ in ready.select(min(remaining, 0.25)):
                        chunk = os.read(key.fd, min(65536, limit + 1 - len(output)))
                        if not chunk:
                            ready.unregister(key.fileobj)
                            continue
                        output.extend(chunk)
                        if len(output) > limit:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                            raise ValueError(f"{label} exceeded the response limit; response discarded and operation stopped.")
            remaining = deadline - time.monotonic()
            try:
                code = process.wait(timeout=max(remaining, 0.01))
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise ValueError(f"{label} timed out; operation stopped.") from None
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    return code, bytes(output)


def checked_client():
    home = Path.home()
    client = home / ".local/share/rayfile-runtime/rayfile-c"
    if str(home) in ("/", "/home") or not home.is_absolute():
        raise ValueError("Refusing an unsafe home for isolated client state.")
    if not shutil.which("bwrap"):
        raise ValueError("bwrap is required for isolated Rayfile runtime state.")
    if not client.is_file() or client.is_symlink():
        raise ValueError("The reviewed managed Rayfile executable is missing.")
    with client.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != CLIENT_SHA256:
            raise ValueError("Rayfile differs from the reviewed 6.7.8.12 executable.")
    return client, home


def inspect_metadata(args):
    client, home = checked_client()
    token = read_token()
    if not token.strip() or CONTROL.search(token):
        raise ValueError("A non-empty single-line token is required.")
    env = os.environ.copy()
    env.pop("RAYFILE_TOKEN", None)
    code, response = read_response(probe_command(client, home, args.target, args.source, token, args.mode), env)
    output = redact(response.decode("utf-8", errors="replace"), token)
    # Render terminal controls literally; credentials never enter retained logs.
    output = "".join(c if c in "\n\t" or ord(c) >= 32 and ord(c) != 127 else repr(c)[1:-1] for c in output)
    print(output[:MAX_RESPONSE], end="" if output.endswith("\n") else "\n")
    if len(output) > MAX_RESPONSE:
        print("[WARN] Native response display truncated at 1 MiB.", file=sys.stderr)
    if native_probe_failed(code, output):
        raise ValueError(f"Native {args.mode} failed (exit {code}); no download was started.")
    print(f"[WARN] Native {args.mode} response only: entry types require SSH inventory. This probe started no download.", file=sys.stderr)
    return 3



def open_directory(path, create=False):
    path = Path(path).absolute()
    if '..' in path.parts:
        raise ValueError('Parent traversal is not allowed.')
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open('/', flags)
    try:
        for part in path.parts[1:]:
            if create:
                try:
                    os.mkdir(part, mode=0o755, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def create_download_stage(destination):
    parent = Path(destination).absolute()
    while not parent.exists() and not parent.is_symlink():
        parent = parent.parent
    fd = open_directory(parent)
    name = '.rayfile-stage-' + uuid.uuid4().hex
    created = False
    try:
        os.mkdir(name, mode=0o700, dir_fd=fd)
        created = True
        stage = parent / name
        owned = os.stat(name, dir_fd=fd, follow_symlinks=False)
        visible = stage.lstat()
        if (owned.st_dev, owned.st_ino) != (visible.st_dev, visible.st_ino):
            raise ValueError('Destination ancestor changed during staging setup.')
        return stage
    except BaseException:
        if created:
            os.environ['CODEX_TEMP_CLEANUP'] = '1'
            os.rmdir(name, dir_fd=fd)
        raise
    finally:
        os.close(fd)


def verify_download(stage, chosen):
    expected = {item['path']: item for item in chosen if item['type'] == 'file'}
    directories = {'.'}
    for name in expected:
        directories.update(str(parent) for parent in safe_relative(name).parents)
    observed = {}
    root_fd = open_directory(stage)
    os.close(root_fd)
    for root, dirs, files in os.walk(stage, followlinks=False):
        for name in dirs + files:
            path = Path(root) / name
            relative = path.relative_to(stage).as_posix()
            item = path.lstat()
            if stat.S_ISDIR(item.st_mode):
                if relative not in directories:
                    raise ValueError('Unexpected directory in download stage.')
            elif stat.S_ISREG(item.st_mode):
                wanted = expected.get(relative)
                if wanted is None or item.st_size != wanted['size']:
                    raise ValueError('Downloaded paths or sizes do not match the selection.')
                observed[relative] = item
            else:
                raise ValueError('Link or special object in download stage.')
    if observed.keys() != expected.keys():
        raise ValueError('Download is incomplete; final destination was not changed.')
    return [(Path(stage) / name, expected[name], observed[name]) for name in sorted(expected)]


def publish_download(verified, destination, collision_name):
    published = []
    try:
        for source, item, checked in verified:
            relative = safe_relative(item['path'])
            current = source.lstat()
            if (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns) != (checked.st_dev, checked.st_ino, checked.st_size, checked.st_mtime_ns):
                raise ValueError('Download stage changed before publication.')
            directory = Path(destination) / relative.parent
            fd = open_directory(directory, create=True)
            try:
                for index in range(10001):
                    name = relative.name if index == 0 else collision_name(relative.name, index)
                    if len(safe_relative(name).parts) != 1:
                        raise ValueError('Invalid collision filename.')
                    try:
                        # Hard links publish complete files without replacing any entry.
                        os.link(source, name, dst_dir_fd=fd, follow_symlinks=False)
                    except FileExistsError:
                        continue
                    except OSError as error:
                        raise ValueError(f'This destination cannot publish with a hard link (errno {error.errno}); no overwrite fallback was used.') from None
                    published.append(str(relative.parent / name))
                    break
                else:
                    raise ValueError('Too many existing collision names.')
            finally:
                os.close(fd)
    except (OSError, ValueError, KeyboardInterrupt) as error:
        if isinstance(error, KeyboardInterrupt):
            error.published = published
            raise
        failure = ValueError(f'Publication stopped after {len(published)} files; existing files were preserved: {error}')
        failure.published = published
        raise failure from None
    return published


def transfer_summary(data):
    text = data.decode('utf-8', errors='replace')
    counts = {}
    for label in ('total', 'success', 'succeeded', 'failed', 'fail', 'skipped', 'skip', 'error'):
        values = re.findall(r'\b' + label + r'(?:\s+files?)?\s*[:=]?\s*[\[(]?\s*(\d+)\b', text, re.I)
        values += re.findall(r'\b(\d+)\s+(?:files?\s+)?' + label + r'\b', text, re.I)
        if values:
            counts[label] = sorted({int(value) for value in values})
    failed = native_probe_failed(0, text) or any(value > 0 for label in ('failed', 'fail', 'error') for value in counts.get(label, []))
    return counts, failed


def read_transfer(command, env):
    tail = bytearray()
    counts = {}
    failed = False
    started = time.monotonic()
    notice = started
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env=env, start_new_session=True) as process:
        try:
            with selectors.DefaultSelector() as ready:
                ready.register(process.stdout, selectors.EVENT_READ)
                while ready.get_map():
                    for key, _ in ready.select(1):
                        chunk = os.read(key.fd, 65536)
                        if not chunk:
                            ready.unregister(key.fileobj)
                            continue
                        tail.extend(chunk)
                        observed, error = transfer_summary(tail)
                        counts.update(observed)
                        failed |= error
                        del tail[:-MAX_RESPONSE]
                    if time.monotonic() - notice >= 30:
                        notice = time.monotonic()
                        print(f'Transfer active: {int(notice - started)} s', file=sys.stderr)
            code = process.wait()
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
    return code, counts, failed


def collision_name(name, index):
    path = Path(name)
    return path.stem + '.' + str(index) + path.suffix


def run_download(args):
    if args.target in ('hfcluster', 'tycluster'):
        print(f'[WARN] {args.target} uses the shared download workflow; real-server transfer has not been tested.', file=sys.stderr)
    entries = ssh_inventory(args.target, args.source)
    chosen = selected_entries(entries, args.prefix, args.suffix)
    files = [item for item in chosen if item['type'] == 'file']
    if not files:
        print('[SKIP] No regular files selected; destination was not changed.')
        return 0
    client, home = checked_client()
    token = read_token()
    if not token.strip() or CONTROL.search(token):
        raise ValueError('A non-empty single-line token is required.')
    env = os.environ.copy()
    env.pop('RAYFILE_TOKEN', None)
    stage = create_download_stage(args.destination)
    stage_identity = stage.stat()
    report = {'schema': 1, 'target': args.target, 'source': args.source,
              'selected_files': len(files), 'completed_batches': 0}
    phase = 'prepare batches'
    try:
        groups = {}
        for item in files:
            groups.setdefault(str(PurePosixPath(item['path']).parent), []).append(item)
        payload = stage / 'payload'
        payload.mkdir()
        for index, (parent, batch) in enumerate(sorted(groups.items()), 1):
            phase = f'download batch {index}/{len(groups)}'
            print(f'[{index}/{len(groups)}] Downloading {len(batch)} files from {parent}', file=sys.stderr)
            batch_stage = stage / f'batch_{index}'
            batch_stage.mkdir()
            filelist = stage / f'list_{index}.txt'
            with filelist.open('x', encoding='utf-8', newline='\n') as stream:
                stream.writelines(args.source + '/' + item['path'] + '\n' for item in batch)
            code, counts, failed = read_transfer(download_command(client, home, args.target, args.source, batch_stage, token, filelist), env)
            report['last_batch'] = {'parent': parent, 'exit': code, 'counts': counts}
            if code or failed:
                raise ValueError(f'Native batch failed (exit {code}); final destination was not changed.')
            flattened = [dict(item, path=PurePosixPath(item['path']).name) for item in batch]
            verify_download(batch_stage, flattened)
            for item in batch:
                target = payload / item['path']
                target.parent.mkdir(parents=True, exist_ok=True)
                os.link(batch_stage / target.name, target, follow_symlinks=False)
            report['completed_batches'] = index
        phase = 'verify source stability'
        if ssh_inventory(args.target, args.source) != entries:
            raise ValueError('SSH source metadata changed during transfer; final destination was not changed.')
        verified = verify_download(payload, chosen)
        phase = 'publish complete files'
        published = publish_download(verified, args.destination, collision_name)
    except BaseException as error:
        report.update({'phase': phase, 'error_type': type(error).__name__,
                       'published_count': len(getattr(error, 'published', [])),
                       'published_preview': getattr(error, 'published', [])[:20]})
        diagnostic = stage.parent / (stage.name + '.failure.json')
        fd = os.open(diagnostic, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(report, stream, ensure_ascii=True, indent=2)
            stream.write('\n')
        print(f'Diagnostic: {diagnostic}', file=sys.stderr)
        raise
    finally:
        current = stage.lstat()
        if (current.st_dev, current.st_ino) != (stage_identity.st_dev, stage_identity.st_ino):
            raise ValueError(f'Stage identity changed; automatic cleanup refused: {stage}')
        os.environ['CODEX_TEMP_CLEANUP'] = '1'
        shutil.rmtree(stage)
    print(f'[OK] Downloaded {len(published)} files; existing files preserved with numbered incoming names.')
    return 0


def main():
    parser = argparse.ArgumentParser(description="Inspect metadata or download hf/ty/wz selections through Rayfile; only WZ has live fixture acceptance.")
    parser.add_argument("mode", choices=("validate", "list", "attributes", "ssh-list", "run"))
    parser.add_argument("--target", choices=HOSTS, required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--prefix", default="")
    parser.add_argument("--suffix", default="")
    args = parser.parse_args()
    try:
        filename_pattern(args.prefix, args.suffix)
        validate_source(args.source)
        destination = Path(args.destination).absolute()
        if destination == Path("/"):
            raise ValueError("Refusing the local root as a destination.")
        for path in (destination, *destination.parents):
            if path.is_symlink() or path.exists() and not path.is_dir():
                raise ValueError("Destination and existing parents must be regular directories.")
        if args.mode == "validate":
            return 0
        if args.mode == "ssh-list":
            return inspect_ssh(args)
        if args.mode == "run":
            return run_download(args)
        return inspect_metadata(args)
    except KeyboardInterrupt:
        print("[ERROR] Operation interrupted; inspect any diagnostic for publication status.", file=sys.stderr)
        return 130
    except (OSError, ValueError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
