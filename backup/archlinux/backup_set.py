#!/usr/bin/env python3

import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import sys
import tarfile
import tempfile
import uuid

FORMAT = 1
CURRENT = 'github-current'
SET_ID = re.compile(r'[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}')
CATALOG = '.backup-manifest.json'
COMPONENTS = ('packages', 'system', 'home', 'credentials', 'dot_files', 'scripts',
              'research_workflow', 'topiary', 'nvim', 'rayfile', 'rebuild')
CONTROL = re.compile(r'[\x00-\x1f\x7f]')


def fail(message):
    raise ValueError(message)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            fail('Duplicate JSON key.')
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=pairs)


def write_json(path, value):
    temp = path.with_name(path.name + '.tmp-' + uuid.uuid4().hex)
    try:
        with temp.open('x', encoding='utf-8') as stream:
            os.chmod(temp, 0o600)
            json.dump(value, stream, sort_keys=True, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            os.environ['CODEX_TEMP_CLEANUP'] = '1'
            temp.unlink()


def safe_path(value):
    if not isinstance(value, str) or not value or CONTROL.search(value) or '\\' in value:
        fail('Unsafe path in manifest/archive.')
    if value.startswith('/') or any(part in ('', '.', '..') for part in value.split('/')):
        fail('Archive paths must be relative without dot segments.')
    return value


def regular_parents(path):
    for item in (path, *path.parents):
        if item.is_symlink() or item.exists() and not item.is_dir():
            fail(f'Not a regular directory: {item}')


def check_links(records):
    nodes = dict(records)
    for name in records:
        for parent in PurePosixPath(name).parents:
            key = str(parent)
            if key == '.':
                continue
            if key in nodes and nodes[key]['type'] != 'directory':
                fail(f'Archive parent is not a directory: {name}')
            nodes.setdefault(key, {'type': 'directory'})
    for name, info in records.items():
        if info['type'] != 'symlink':
            continue
        pending = name.split('/')
        resolved = []
        expansions = 0
        while pending:
            part = pending.pop(0)
            if part in ('', '.'):
                continue
            if part == '..':
                if not resolved:
                    fail(f'Archive link escapes target: {name}')
                resolved.pop()
                continue
            resolved.append(part)
            current = '/'.join(resolved)
            node = nodes.get(current)
            if node is None:
                fail(f'Archive link target is missing: {name}')
            if node['type'] == 'symlink':
                value = node['target']
                if not value or value.startswith('/') or CONTROL.search(value) or '\\' in value:
                    fail(f'Unsafe archive link: {current}')
                expansions += 1
                if expansions > 40:
                    fail(f'Archive link cycle or excessive depth: {name}')
                resolved.pop()
                pending = value.split('/') + pending
            elif pending and node['type'] != 'directory':
                fail(f'Archive link traverses a non-directory: {name}')
        final = '/'.join(resolved)
        if not final or name.startswith(final + '/'):
            fail(f'Archive directory link cycle: {name}')


def check_resolved_links(root, records):
    base = root.resolve(strict=True)
    for name, info in records.items():
        if info['type'] == 'symlink':
            try:
                resolved = (root / name).resolve(strict=True)
            except (OSError, RuntimeError) as error:
                fail(f'Invalid staged link: {name}: {error}')
            if not resolved.is_relative_to(base):
                fail(f'Staged link escapes target: {name}')


def synthetic_directories(root, extra=()):
    result = set(extra)
    if (root / CATALOG).is_file() and not (root / CATALOG).is_symlink():
        value = read_json(root / CATALOG)
        result.update(value.get('synthetic_directories', []))
    for name in result:
        safe_path(name)
        if not (root / name).is_dir() or (root / name).is_symlink():
            fail(f'Synthetic parent is not a directory: {name}')
    return result


def inventory(root):
    regular_parents(root)
    if not root.is_dir():
        fail('Inventory source must be an existing directory.')
    result = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(base) / name
            rel = path.relative_to(root).as_posix()
            if rel == CATALOG:
                continue
            safe_path(rel)
            mode = path.lstat().st_mode
            record = {'mode': stat.S_IMODE(mode) & 0o777}
            if stat.S_ISLNK(mode):
                record.update(type='symlink', target=os.readlink(path))
            elif stat.S_ISDIR(mode):
                record.update(type='directory')
            elif stat.S_ISREG(mode):
                record.update(type='file', size=path.stat().st_size, sha256=digest(path))
            else:
                fail(f'Unsupported file type: {rel}')
            result[rel] = record
    check_links(result)
    check_resolved_links(root, result)
    return result


def archive_records(archive, require_catalog=False):
    if archive.is_symlink() or not archive.is_file():
        fail('Archive must be a regular file.')
    records, members, catalog = {}, {}, None
    root_seen = False
    with tarfile.open(archive, 'r:gz') as stream:
        for member in stream:
            name = member.name
            while name.startswith('./'):
                name = name[2:]
            name = name.rstrip('/')
            if name in ('', '.'):
                if member.isdir() and not root_seen:
                    root_seen = True
                    continue
                fail('Invalid root archive member.')
            safe_path(name)
            if name in members:
                fail(f'Duplicate archive path: {name}')
            members[name] = member
            record = {'mode': member.mode & 0o777}
            if member.isfile():
                if member.size < 0:
                    fail('Negative archive size.')
                with stream.extractfile(member) as source:
                    record.update(type='file', size=member.size,
                                  sha256=hashlib.file_digest(source, 'sha256').hexdigest())
                if name == CATALOG:
                    if member.size > 32 * 1024 * 1024:
                        fail('Internal manifest is too large.')
                    catalog = json.load(stream.extractfile(member), object_pairs_hook=pairs)
                    continue
            elif member.isdir():
                record.update(type='directory')
            elif member.issym():
                record.update(type='symlink', target=member.linkname)
            else:
                fail(f'Unsupported archive member type: {name}')
            records[name] = record
        check_links(records)
    if catalog is not None:
        if not isinstance(catalog, dict) or catalog.get('format') != FORMAT or catalog.get('files') != records:
            fail('Archive members differ from the internal manifest.')
        synthetic = catalog.get('synthetic_directories', [])
        if not isinstance(synthetic, list) or any(name not in records or records[name]['type'] != 'directory' for name in synthetic):
            fail('Invalid synthetic-directory manifest.')
    elif require_catalog:
        fail('Archive lacks its internal manifest.')
    return records, members, catalog


def stage(archive, target, require_catalog):
    before = digest(archive)
    records, members, catalog = archive_records(archive, require_catalog)
    regular_parents(target)
    if target.exists() and any(target.iterdir()):
        fail('Archive staging requires a new or empty directory.')
    ancestor = target
    while not ancestor.exists():
        ancestor = ancestor.parent
    needed = sum(row.get('size', 0) for row in records.values())
    if shutil.disk_usage(ancestor).free < needed + 64 * 1024 * 1024:
        fail('Insufficient staging space.')
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tarfile.open(archive, 'r:gz') as stream:
        for name, row in sorted(records.items(), key=lambda item: (len(PurePosixPath(item[0]).parts), item[0])):
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if row['type'] == 'directory':
                path.mkdir(exist_ok=True)
            elif row['type'] == 'file':
                with stream.extractfile(members[name]) as source, path.open('xb') as dest:
                    shutil.copyfileobj(source, dest)
                os.chmod(path, row['mode'])
            else:
                path.symlink_to(row['target'])
        for name, row in sorted(records.items(), reverse=True):
            if row['type'] == 'directory':
                os.chmod(target / name, row['mode'])
    if digest(archive) != before:
        fail('Archive changed during staging.')
    if inventory(target) != records:
        fail('Staged content differs from the archive.')
    write_json(target / CATALOG, {'format': FORMAT, 'files': records,
               'synthetic_directories': catalog.get('synthetic_directories', []) if catalog else []})
    return {'files': len(records), 'bytes': needed}


def init_set(root):
    regular_parents(root)
    root.mkdir(parents=True, exist_ok=True)
    name = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:12]
    target = root / name
    target.mkdir(mode=0o700)
    identity = temp_identity(target)
    try:
        write_json(target / 'manifest.json', {'format': FORMAT, 'id': name, 'state': 'INCOMPLETE',
                   'architecture': platform.machine(), 'created_at': datetime.now(timezone.utc).isoformat(),
                   'components': {}})
        print(target, flush=True)
    except BaseException:
        os.environ['CODEX_TEMP_CLEANUP'] = '1'
        cleanup_owned(target, identity)
        raise


def load_set(root, complete=False):
    regular_parents(root)
    if (root / 'manifest.json').is_symlink() or not (root / 'manifest.json').is_file():
        fail('Manifest must be a regular file.')
    manifest = read_json(root / 'manifest.json')
    if not isinstance(manifest, dict) or manifest.get('format') != FORMAT:
        fail('Unsupported backup-set manifest.')
    identity = manifest.get('id')
    if root.name == CURRENT:
        if not complete or not isinstance(identity, str) or not SET_ID.fullmatch(identity):
            fail('Invalid published backup identity.')
    elif identity != root.name:
        fail('Unsupported backup-set manifest or mismatched identity.')
    if manifest.get('architecture') != platform.machine():
        fail('Backup architecture differs from this machine.')
    if complete:
        if manifest.get('state') != 'COMPLETE' or (root / 'COMPLETE').is_symlink() or not (root / 'COMPLETE').is_file():
            fail('Backup set is incomplete.')
        if (root / 'COMPLETE').read_text(encoding='utf-8').strip() != digest(root / 'manifest.json'):
            fail('Backup completion marker differs from the manifest.')
    return manifest


def check_components(root, manifest):
    if not isinstance(manifest.get('components'), dict) or set(manifest['components']) != set(COMPONENTS):
        fail('Backup set lacks a required component decision.')
    expected = {'manifest.json', 'COMPLETE'}
    for name, row in manifest['components'].items():
        if not isinstance(row, dict):
            fail('Invalid component metadata.')
        if row.get('state') == 'absent':
            if name in ('packages', 'scripts', 'dot_files', 'research_workflow', 'nvim', 'rebuild'):
                fail(f'Required component absent: {name}')
            if not row.get('reason'):
                fail('Absent component needs a reason.')
            continue
        if row.get('state') != 'present':
            fail('Unknown component state.')
        filename = safe_path(row['file'])
        suffix = '.tar.gz.gpg' if name in ('credentials', 'dot_files') else '.tar.gz'
        if filename != name + suffix:
            fail(f'Unexpected payload filename: {name}')
        if '/' in filename or filename in expected:
            fail('Duplicate or nested payload filename.')
        expected.add(filename)
        path = root / filename
        if path.is_symlink() or not path.is_file() or path.stat().st_size != row['size'] or digest(path) != row['sha256']:
            fail(f'Backup payload changed: {name}')
        if filename.endswith('.tar.gz'):
            archive_records(path, name not in ('nvim', 'rayfile'))
    if set(p.name for p in root.iterdir()) - expected:
        fail('Unexpected files in backup set.')


def publish_set(root):
    if not SET_ID.fullmatch(root.name):
        fail('Publication requires a generated set directory.')
    manifest = load_set(root, complete=True)
    check_components(root, manifest)
    if any(p.stat().st_size > 100 * 1024 * 1024 for p in root.iterdir()):
        fail('A component exceeds the 100 MiB per-file Git publication limit.')
    current = root.parent / CURRENT
    replacing = current.exists() or current.is_symlink()
    if replacing:
        previous_id = temp_identity(current)
        previous = load_set(current, complete=True)
        check_components(current, previous)
    # Linux NOREPLACE for first publication, EXCHANGE for subsequent backups.
    rename = ctypes.CDLL(None, use_errno=True).renameat2
    if rename(-100, os.fsencode(root), -100, os.fsencode(current), 2 if replacing else 1):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), str(current))
    if replacing:
        os.environ['CODEX_TEMP_CLEANUP'] = '1'
        cleanup_owned(root, previous_id)


def compare(source, target, synthetic=(), excluded=()):
    source_rows = inventory(source)
    synthetic = synthetic_directories(source, synthetic)
    regular_parents(target.parent)
    if target.is_symlink() or target.exists() and not target.is_dir():
        fail('Restore target root is not a regular directory.')
    result = []
    blocked = set()
    for value in excluded:
        safe_path(value)
    for name, row in sorted(source_rows.items(), key=lambda item: (len(PurePosixPath(item[0]).parts), item[0])):
        if any(name == value or name.startswith(value + '/') for value in excluded):
            continue
        path = target / name
        before = None
        if any(str(p) in blocked for p in PurePosixPath(name).parents):
            action = 'new'
        elif not path.exists() and not path.is_symlink():
            action = 'new'
        else:
            mode = path.lstat().st_mode
            before = {'mode': stat.S_IMODE(mode)}
            if stat.S_ISDIR(mode): before.update(type='directory')
            elif stat.S_ISLNK(mode): before.update(type='symlink', target=os.readlink(path))
            elif stat.S_ISREG(mode): before.update(type='file', size=path.stat().st_size, sha256=digest(path))
            else: fail(f'Unsupported destination type: {path}')
            if before['type'] == row['type'] == 'directory':
                action = 'same' if name in synthetic or before == row else 'metadata'
            else:
                action = 'same' if before == row else 'change'
        if row['type'] == 'directory' and action == 'change':
            blocked.add(name)
        result.append({'path': name, 'action': action, 'type': row['type'], 'before': before, 'after': row})
    return result


def content_info(path):
    regular_parents(path.parent)
    if path.is_symlink() or not path.is_file():
        fail('Content comparison requires a regular file with regular parents.')
    return {'type': 'file', 'mode': stat.S_IMODE(path.stat().st_mode),
            'size': path.stat().st_size, 'sha256': digest(path)}


def authority_state(source, target):
    expected, current = {}, {}
    for name in ('metadata', 'policy'):
        if not (source / name).is_dir():
            fail(f'Portable authority source is missing: {name}')
        for root, result in ((source, expected), (target, current)):
            path = root / name
            if not path.exists() and not path.is_symlink():
                continue
            for relative, row in inventory(path).items():
                if row['type'] == 'symlink':
                    fail('Portable authority must not contain links.')
                result[name + '/' + relative] = {key: value for key, value in row.items() if key != 'mode'}
    if not any(row['type'] == 'file' for row in current.values()):
        return {'state': 'empty', 'reason': 'No destination portable authority files; import may proceed.'}
    if current == expected:
        return {'state': 'same', 'reason': 'Portable authority members and bytes match; skip metadata and policy.'}
    changed = sorted(name for name in expected.keys() | current.keys() if expected.get(name) != current.get(name))
    return {'state': 'conflict', 'reason': 'Existing portable authority differs. Use the authorized Research_Workflow merge/validate workflow; this restore cannot overwrite or combine journals.', 'paths': changed}


def temp_identity(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        if info.st_uid != os.geteuid():
            fail('Temporary directory is not owned by this invocation user.')
        return f'{info.st_dev}:{info.st_ino}'
    finally:
        os.close(descriptor)


def create_temp(prefix):
    if not re.fullmatch(r'arch-(?:backup|restore-(?:runner|payload|user|yay))\.', prefix):
        fail('Unsupported temporary-directory prefix.')
    path = Path(tempfile.mkdtemp(prefix=prefix, dir='/tmp'))
    identity = temp_identity(path)
    try:
        print(f'{path}\t{identity}', flush=True)
    except BaseException:
        os.environ['CODEX_TEMP_CLEANUP'] = '1'
        cleanup_owned(path, identity)
        raise


def cleanup_owned(path, identity):
    if os.environ.get('CODEX_TEMP_CLEANUP') != '1':
        fail('Temporary cleanup requires CODEX_TEMP_CLEANUP=1.')
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return
    try:
        info = os.fstat(descriptor)
        if identity != f'{info.st_dev}:{info.st_ino}':
            fail('Temporary directory identity changed; nothing removed.')
        def clear_directory(directory):
            os.fchmod(directory, stat.S_IMODE(os.fstat(directory).st_mode) | 0o700)
            for name in os.listdir(directory):
                child = os.stat(name, dir_fd=directory, follow_symlinks=False)
                if stat.S_ISDIR(child.st_mode):
                    path_descriptor = os.open(name, os.O_PATH | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
                    try:
                        held = os.fstat(path_descriptor)
                        if (held.st_dev, held.st_ino) != (child.st_dev, child.st_ino):
                            fail('Temporary child identity changed; cleanup stopped.')
                        os.chmod(f'/proc/self/fd/{path_descriptor}', stat.S_IMODE(held.st_mode) | 0o700)
                        nested = os.open('.', os.O_RDONLY | os.O_DIRECTORY, dir_fd=path_descriptor)
                        try:
                            clear_directory(nested)
                        finally:
                            os.close(nested)
                        current_child = os.stat(name, dir_fd=directory, follow_symlinks=False)
                        if (current_child.st_dev, current_child.st_ino) != (held.st_dev, held.st_ino):
                            fail('Temporary child moved; its replacement is retained.')
                        os.rmdir(name, dir_fd=directory)
                    finally:
                        os.close(path_descriptor)
                else:
                    os.unlink(name, dir_fd=directory)
        clear_directory(descriptor)
        current = path.lstat()
        if stat.S_ISLNK(current.st_mode) or (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
            fail('Temporary directory moved; contents cleared through its original descriptor only.')
        path.rmdir()
    finally:
        os.close(descriptor)


def rayfile_equivalent(source, home, helper):
    import importlib.util
    spec = importlib.util.spec_from_file_location('rayfile_state', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.validate_snapshot(source)
    runtime = home / '.local/share/rayfile-runtime'
    launcher = home / '.local/bin/rayfile-c'
    try:
        module.regular_parents(runtime.parent)
        module.regular_parents(launcher.parent)
        module.validate_runtime(runtime)
        module.regular_file(launcher)
        if launcher.read_text(encoding='utf-8') != module.launcher_text(home) or stat.S_IMODE(launcher.stat().st_mode) != 0o755:
            return {'equivalent': False, 'reason': 'Launcher differs.'}
        if any(module.digest(runtime / name) != module.digest(source / 'rayfile-runtime' / name)
               or stat.S_IMODE((runtime / name).stat().st_mode) != stat.S_IMODE((source / 'rayfile-runtime' / name).stat().st_mode)
               for name in module.RUNTIME_FILES):
            return {'equivalent': False, 'reason': 'Runtime content differs.'}
        return {'equivalent': True, 'reason': 'All managed runtime bytes and the target-home launcher match.'}
    except (OSError, RuntimeError, ValueError, KeyError, TypeError):
        return {'equivalent': False, 'reason': 'Managed runtime or launcher is absent, unsafe or changed.'}


def main():
    parser = argparse.ArgumentParser(description='Inspect immutable Arch backup sets, archives and restore differences.')
    sub = parser.add_subparsers(dest='command', required=True)
    cmd = sub.add_parser('init'); cmd.add_argument('root', type=Path)
    cmd = sub.add_parser('record'); cmd.add_argument('root', type=Path); cmd.add_argument('name', choices=COMPONENTS)
    cmd.add_argument('--file'); cmd.add_argument('--absent')
    for name in ('seal', 'verify', 'publish'):
        cmd = sub.add_parser(name); cmd.add_argument('root', type=Path)
    cmd = sub.add_parser('catalog'); cmd.add_argument('root', type=Path)
    cmd.add_argument('--synthetic-directory', action='append', default=[])
    cmd = sub.add_parser('parents'); cmd.add_argument('root', type=Path)
    for name in ('inspect', 'stage'):
        cmd = sub.add_parser(name); cmd.add_argument('archive', type=Path); cmd.add_argument('--require-catalog', action='store_true')
        if name == 'stage': cmd.add_argument('target', type=Path)
    cmd = sub.add_parser('content-info'); cmd.add_argument('path', type=Path)
    cmd = sub.add_parser('authority-state'); cmd.add_argument('source', type=Path); cmd.add_argument('target', type=Path)
    cmd = sub.add_parser('temp-create'); cmd.add_argument('prefix')
    cmd = sub.add_parser('temp-id'); cmd.add_argument('root', type=Path)
    cmd = sub.add_parser('check-temp'); cmd.add_argument('root', type=Path); cmd.add_argument('identity')
    cmd = sub.add_parser('cleanup'); cmd.add_argument('root', type=Path); cmd.add_argument('identity')
    cmd = sub.add_parser('rayfile-equivalent'); cmd.add_argument('source', type=Path); cmd.add_argument('home', type=Path); cmd.add_argument('helper', type=Path)
    cmd = sub.add_parser('diff'); cmd.add_argument('source', type=Path); cmd.add_argument('target', type=Path); cmd.add_argument('--nul', action='store_true')
    cmd.add_argument('--synthetic-directory', action='append', default=[])
    cmd.add_argument('--exclude-path', action='append', default=[])
    args = parser.parse_args()
    try:
        if args.command == 'init':
            init_set(args.root.absolute()); return 0
        if args.command == 'publish':
            publish_set(args.root.absolute()); return 0
        if args.command in ('record', 'seal', 'verify'):
            root = args.root.absolute(); manifest = load_set(root, args.command == 'verify')
            if args.command != 'verify' and (manifest['state'] != 'INCOMPLETE' or (root / 'COMPLETE').exists()):
                fail('Completed backup sets are immutable.')
            if args.command == 'record':
                if bool(args.file) == bool(args.absent): fail('Choose --file or --absent.')
                if args.name in manifest['components']: fail('Component already recorded.')
                if args.file:
                    filename = safe_path(args.file)
                    if '/' in filename: fail('Payload must be directly inside this set.')
                    path = root / filename
                    if path.is_symlink() or not path.is_file(): fail('Payload is not a regular file.')
                    row = {'state': 'present', 'file': filename, 'size': path.stat().st_size, 'sha256': digest(path)}
                else: row = {'state': 'absent', 'reason': args.absent}
                manifest['components'][args.name] = row
                write_json(root / 'manifest.json', manifest)
            else:
                check_components(root, manifest)
                if args.command == 'seal':
                    manifest['state'] = 'COMPLETE'; write_json(root / 'manifest.json', manifest)
                    with (root / 'COMPLETE').open('x', encoding='utf-8') as stream:
                        stream.write(digest(root / 'manifest.json') + '\n'); stream.flush(); os.fsync(stream.fileno())
                print(json.dumps(manifest, sort_keys=True))
        elif args.command == 'content-info':
            print(json.dumps(content_info(args.path.absolute()), sort_keys=True))
        elif args.command == 'authority-state':
            result = authority_state(args.source.absolute(), args.target.absolute())
            print(json.dumps(result, sort_keys=True))
            if result['state'] == 'conflict': return 1
        elif args.command == 'temp-create':
            create_temp(args.prefix)
        elif args.command == 'temp-id':
            print(temp_identity(args.root.absolute()))
        elif args.command == 'check-temp':
            if temp_identity(args.root.absolute()) != args.identity:
                fail('Temporary directory identity changed.')
        elif args.command == 'cleanup':
            cleanup_owned(args.root.absolute(), args.identity)
        elif args.command == 'rayfile-equivalent':
            print(json.dumps(rayfile_equivalent(args.source.absolute(), args.home.absolute(), args.helper.absolute())))
        elif args.command == 'parents':
            regular_parents(args.root.absolute())
        elif args.command == 'catalog':
            root = args.root.absolute()
            if (root / CATALOG).exists() or (root / CATALOG).is_symlink(): fail('Internal manifest already exists.')
            write_json(root / CATALOG, {'format': FORMAT, 'files': inventory(root),
                       'synthetic_directories': sorted(synthetic_directories(root, args.synthetic_directory))})
        elif args.command == 'inspect':
            records, _, _ = archive_records(args.archive, args.require_catalog)
            print(json.dumps({'files': len(records), 'bytes': sum(row.get('size', 0) for row in records.values())}))
        elif args.command == 'stage':
            print(json.dumps(stage(args.archive, args.target.absolute(), args.require_catalog)))
        elif args.command == 'diff':
            rows = compare(args.source.absolute(), args.target.absolute(), args.synthetic_directory, args.exclude_path)
            if args.nul:
                for row in rows:
                    if row['action'] != 'same':
                        detail = json.dumps({'before': row['before'], 'after': row['after']}, sort_keys=True)
                        sys.stdout.buffer.write((row['action']+'\0'+row['path']+'\0'+row['type']+'\0'+detail+'\0').encode('utf-8'))
            else: print(json.dumps(rows, indent=2))
        return 0
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        print(f'[ERROR] {error}', file=sys.stderr); return 1


if __name__ == '__main__':
    raise SystemExit(main())
