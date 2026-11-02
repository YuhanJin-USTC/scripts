"""Capture published sources and rebuild downloads inside caller-owned staging."""

import argparse
import json
import os
import platform
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import urllib.request

import backup_set as sets
import nvim_state as nvim
import rayfile_state as rayfile

PROJECTS = {'dot_files': 'dot_files', 'research_workflow': 'Research_Workflow'}
NU_REVISION = '18b7f951e0c511f854685dfcc9f6a34981101dd6'


def run(args, **kwargs):
    try:
        result = sets.run_process([str(x) for x in args], timeout=kwargs.pop('timeout', 300), **kwargs)
    except subprocess.TimeoutExpired as error:
        detail = error.stderr or ''
        if isinstance(detail, bytes):
            detail = detail.decode(errors='replace')
        raise RuntimeError(f'{args[0]} timed out after {error.timeout}s. {detail.strip()[-1500:]}'.rstrip()) from None
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {(result.stderr + result.stdout).strip()[-2500:]}')
    return result.stdout.strip()


def git(path, *args):
    return run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-C', path, *args],
               env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0', 'GIT_TERMINAL_PROMPT': '0'})


def url(value):
    if not isinstance(value, str) or not re.fullmatch(r'(?:https://github.com/|git@github.com:)[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?', value):
        raise ValueError('Expected a GitHub HTTPS or SSH repository URL without credentials.')
    return value


def published(path, scratch, *, plugin=False, scripts=False):
    sets.regular_parents(path)
    if not (path / '.git').is_dir() or (path / '.git').is_symlink():
        raise RuntimeError(f'Expected a regular Git checkout: {path}')
    args = ['status', '--porcelain', '--untracked-files=no' if plugin else '--untracked-files=all']
    if scripts:
        args += ['--', '.', ':(exclude)backup/archlinux/data', ':(exclude)backup/archlinux/pkg_lists']
    changes = git(path, *args).splitlines()
    if changes:
        raise RuntimeError(f'Uncommitted files in {path}; commit and push first:\n' + '\n'.join(changes[:15]))
    remote = url(git(path, 'remote', 'get-url', 'origin'))
    commit = git(path, 'rev-parse', 'HEAD')
    branch = git(path, 'branch', '--show-current')
    refs = git(path, 'for-each-ref', '--format=%(objectname)', 'refs/heads').splitlines() if not plugin else []
    probe = scratch / 'remote.git'
    if not probe.exists():
        run(['git', 'init', '--bare', '-q', probe])
    for revision in sorted(set([commit, *refs])):
        try:
            run(['git', '-c', 'core.hooksPath=/dev/null', '--git-dir', probe, 'fetch', '--quiet',
                 '--depth=1', '--filter=blob:none', '--no-tags', '--', remote, revision],
                env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'})
        except RuntimeError as error:
            raise RuntimeError(f'{path}: commit {revision[:12]} is not confirmed on origin; push it or fix network access. {error}') from None
    return {'url': remote, 'commit': commit, 'branch': branch}


def download(source, target, expected):
    if not isinstance(source, str) or not source.startswith('https://') or not isinstance(expected, str) or not re.fullmatch(r'[0-9a-f]{64}', expected):
        raise ValueError('Download requires HTTPS and a SHA256 pin.')
    request = urllib.request.Request(source, headers={'User-Agent': 'arch-config-restore/2'})
    with urllib.request.urlopen(request, timeout=120) as response, target.open('xb') as stream:
        shutil.copyfileobj(response, stream)
    if sets.digest(target) != expected:
        raise RuntimeError(f'Download changed: {source}; expected SHA256 {expected}.')


def clone(record, target, source=None):
    remote = url(record['url'])
    commit = record['commit']
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Invalid repository commit.')
    target.mkdir()
    git(target, 'init', '--quiet')
    git(target, 'remote', 'add', 'origin', remote)
    branch = record.get('branch')
    refs = [commit]
    if branch:
        git(target, 'check-ref-format', '--branch', branch)
        refs.append(f'refs/heads/{branch}:refs/remotes/origin/{branch}')
    # Projects need ancestry for fast-forward checks. Plugins need just the pin.
    depth = [] if 'branch' in record else ['--depth=1']
    operation = 'fetch from local checkout' if source else 'fetch from origin'
    try:
        git(target, 'fetch', '--no-tags', '--no-recurse-submodules', *depth, '--', source or 'origin', *refs)
        operation = 'checkout'
        git(target, 'checkout', '--quiet', *(['-B', branch] if branch else ['--detach']), commit)
        if git(target, 'rev-parse', 'HEAD') != commit:
            raise RuntimeError('Checked-out commit differs from the backup.')
        if branch:
            git(target, 'branch', '--set-upstream-to=origin/' + branch)
    except RuntimeError as error:
        raise RuntimeError(f'{target.name} {operation} {commit[:12]}: {error}') from None


def config_digests(root, names):
    result = {}
    for name in names:
        path = root / sets.safe_path(name)
        if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise RuntimeError(f'Missing or external configuration source: {path}')
        result[name] = sets.digest(path)
    return result


def capture(home, scratch):
    records = {name: published(home / directory, scratch) for name, directory in PROJECTS.items()}
    published(home / 'scripts', scratch, scripts=True)
    for effective, repository in (('.gitconfig', 'git/.gitconfig'), ('.config/rclone/rclone.conf', 'rclone/.config/rclone/rclone.conf')):
        left, right = home / effective, home / 'dot_files' / repository
        if left.is_file() and right.is_file() and sets.digest(left) != sets.digest(right):
            raise RuntimeError(f'{effective} differs from dot_files; reconcile and publish it before backup.')
    current = nvim.active_id(nvim.root_for(home))
    if not current:
        raise RuntimeError('No accepted Neovim generation.')
    active = nvim.generation(nvim.root_for(home), current)
    manifest = nvim.read_json(active / 'manifest.json')
    if manifest.get('format') != 2 or manifest.get('architecture') != platform.machine():
        raise RuntimeError('Unsupported editor manifest or architecture.')
    if not manifest.get('validated') or manifest.get('status') != 'validated':
        raise RuntimeError('The active Neovim generation is not validated.')
    prefix = 'nvim/.config/nvim/'
    names = [name[len(prefix):] for name in git(home / 'dot_files', 'ls-files', '-z', '--', prefix).split('\0')
             if name.startswith(prefix) and name != prefix + 'lazy-lock.json']
    if 'init.lua' not in names or 'lua/plugin_specs.lua' not in names:
        raise RuntimeError('Published Neovim configuration lacks its core startup files.')
    active_config = config_digests(active / 'config/nvim', [*names, 'lazy-lock.json'])
    published_config = config_digests(home / 'dot_files/nvim/.config/nvim', names)
    if {k: v for k, v in active_config.items() if k != 'lazy-lock.json'} != {k: v for k, v in published_config.items() if k != 'lazy-lock.json'}:
        raise RuntimeError('Active Neovim configuration differs from dot_files; publish the accepted configuration first.')
    plugins = {}
    for name, row in manifest['plugins'].items():
        if not nvim.NAME.fullmatch(name) or not nvim.COMMIT.fullmatch(row['commit']):
            raise RuntimeError('Invalid plugin source record.')
        item = published(active / 'data/nvim/lazy' / name, scratch, plugin=True)
        if item['commit'] != row['commit']:
            raise RuntimeError(f'Active plugin differs from its accepted pin: {name}')
        plugins[name] = {'url': item['url'], 'commit': item['commit']}
    editor = {key: manifest[key] for key in ('architecture', 'nvim_version', 'runtime_source', 'selection_specs', 'parsers', 'grammars')}
    editor.update(plugins=plugins, config_sha256=active_config,
                  lockfile=(active / 'config/nvim/lazy-lock.json').read_text(encoding='utf-8'))
    topiary = None
    if Path('/usr/local/bin/topiary').exists():
        version = run(['/usr/local/bin/topiary', '--version'])
        match = re.fullmatch(r'topiary-cli (\d+\.\d+\.\d+)', version)
        if not match:
            raise RuntimeError('Topiary requires a released topiary-cli version.')
        version = match[1]
        request = urllib.request.Request('https://crates.io/api/v1/crates/topiary-cli/' + version,
                                         headers={'User-Agent': 'arch-config-backup/2'})
        with urllib.request.urlopen(request, timeout=30) as response:
            package = json.load(response)['version']
        topiary = {'version': version, 'url': f'https://static.crates.io/crates/topiary-cli/topiary-cli-{version}.crate',
                   'sha256': package['checksum'], 'grammar_revision': NU_REVISION}
    client = None
    runtime = home / '.local/share/rayfile-runtime'
    if runtime.exists():
        value = rayfile.validate_runtime(runtime)
        if value['archive_sha256'] != rayfile.ARCHIVE_SHA256 or value['binary_sha256'] != rayfile.BINARY_SHA256:
            raise RuntimeError('Rayfile differs from the pinned downloadable client.')
        client = {key: value[key] for key in ('source_url', 'archive_sha256', 'binary_sha256', 'version', 'architecture')}
    return {'format': 1, 'projects': records, 'nvim': editor, 'topiary': topiary, 'rayfile': client}


def check_targets(home, scratch, selected=None):
    for name, directory in {'scripts': 'scripts', **PROJECTS}.items():
        if selected and name != selected:
            continue
        path = home / directory
        if path.exists() or path.is_symlink():
            published(path, scratch, scripts=directory == 'scripts')


def stage_projects(recipe, home, stage, scratch, keep_workflow=False, selected=None):
    for name, directory in PROJECTS.items():
        if (selected and name != selected) or (name == 'research_workflow' and keep_workflow):
            continue
        record = recipe['projects'][name]
        dest = stage / name
        local = home / directory
        source = None
        old = None
        if local.exists():
            if url(git(local, 'remote', 'get-url', 'origin')) != record['url']:
                raise RuntimeError(f'Repository origin differs: {local}')
            old = git(local, 'rev-parse', 'HEAD')
            if git(local, 'branch', '--show-current') != record['branch']:
                raise RuntimeError(f'Project branch differs from the backup: {local}; select the intended branch first.')
            if old == record['commit'] and git(local, 'rev-parse', '--is-shallow-repository') == 'false':
                keys = git(local, 'config', '--local', '--name-only', '--list').splitlines()
                if not any(key == 'extensions.partialclone' or key.endswith(('.promisor', '.partialclonefilter')) for key in keys):
                    source = local
        print(f'[SOURCE] {directory} {record["commit"][:12]} ({"local" if source else "origin"})', flush=True)
        clone(record, dest, source)
        if old is not None:
            # A newer/divergent target needs a fresh backup, never a history reset.
            git(dest, 'merge-base', '--is-ancestor', old, record['commit'])
            if name == 'research_workflow':
                for relative in ('workspace.toml',):
                    source = local / relative
                    if source.exists():
                        if source.is_symlink() or (dest / relative).exists():
                            raise RuntimeError('Device-local workspace.toml must not be tracked or linked.')
                        shutil.copy2(source, dest / relative)
                before = sets.authority_rows(local)
                after = sets.authority_rows(dest)
                for directory_name in ('metadata', 'policy'):
                    if any(after.get(key) != value for key, value in before.items() if key.startswith(directory_name + '/')):
                        raise RuntimeError('Research_Workflow would replace existing authority; synchronize it and make a fresh backup first.')


def build_editor(recipe, config, target, home):
    record = recipe['nvim']
    if record['architecture'] != platform.machine():
        raise RuntimeError('Neovim architecture differs from the backup.')
    names = [name for name in record['config_sha256'] if name != 'lazy-lock.json']
    if config_digests(config, names) != {k: v for k, v in record['config_sha256'].items() if k != 'lazy-lock.json'}:
        raise RuntimeError('Published Neovim configuration differs from the backup pin.')
    candidate = target.parent / 'editor-build'
    candidate.mkdir()
    try:
        for name in ('config', 'data/nvim/lazy', 'cache', 'state', 'logs', 'tmp'):
            (candidate / name).mkdir(parents=True, exist_ok=True)
        for name in names:
            dest = candidate / 'config/nvim' / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(config / name, dest)
        (candidate / 'config/nvim/lazy-lock.json').write_text(record['lockfile'], encoding='utf-8')
        if nvim.files_digest(candidate / 'config/nvim') != record['config_sha256']:
            raise RuntimeError('Recorded active lockfile/configuration checksum differs.')
        runtime = record['runtime_source']
        print(f'[nvim] Fetching {runtime["tag"]} and {len(record["plugins"])} pinned plugins.', file=sys.stderr, flush=True)
        archive = candidate / 'runtime.tar.gz'
        download(runtime['url'], archive, runtime['archive_sha256'])
        unpack = candidate / 'unpack'
        nvim.safe_extract(archive, unpack)
        roots = list(unpack.iterdir())
        if len(roots) != 1 or not (roots[0] / 'bin/nvim').is_file():
            raise RuntimeError('Unexpected Neovim runtime layout.')
        roots[0].rename(candidate / 'runtime')
        for name, plugin in record['plugins'].items():
            if not nvim.NAME.fullmatch(name):
                raise ValueError('Invalid plugin name.')
            clone(plugin, candidate / 'data/nvim/lazy' / name)
        manifest = {**record, 'format': 2, 'generation': 'downloaded', 'status': 'prepared',
                    'validated': False, 'keep_versions': True}
        nvim.write_json(candidate / 'manifest.json', manifest)
        if json.loads(nvim.helper_run(candidate, home, 'inventory')) != record['grammars']:
            raise RuntimeError('Parser sources differ from the recorded grammar revisions.')
        nvim.helper_run(candidate, home, 'build')
        site = candidate / 'data/nvim/site'
        nvim.tree_copy(site, candidate / 'site-copy')
        nvim.cleanup(site)
        (candidate / 'site-copy').rename(site)
        # Startup initialization is performed after the original-path Mason tools exist.
        manifest['payload_sha256'] = nvim.payload_hashes(candidate)
        manifest['payload_executables'] = nvim.payload_executables(candidate)
        manifest.update(validated=False, reconstructed=True, status='prepared', validation='sources-and-build-only; full validation required on import')
        target.mkdir()
        for old, new in (('config/nvim', 'config'), ('data/nvim/lazy', 'plugins'), ('data/nvim/site', 'site'), ('runtime', 'runtime')):
            (candidate / old).rename(target / new)
        nvim.write_json(target / 'manifest.json', manifest)
        nvim.validated_stage_identity(target)
    finally:
        nvim.cleanup(candidate)


def build_topiary(record, config, target):
    target.mkdir()
    archive = target / 'source.crate'
    download(record['url'], archive, record['sha256'])
    nvim.safe_extract(archive, target / 'source')
    source = target / 'source' / ('topiary-cli-' + record['version'])
    if not (source / 'Cargo.lock').is_file():
        raise RuntimeError('Topiary source lacks Cargo.lock; refusing an unpinned build.')
    env = {**os.environ, 'CARGO_HOME': str(target / 'cargo'), 'CARGO_TARGET_DIR': str(target / 'build'),
           'TMPDIR': str(target / 'tmp'), 'XDG_CACHE_HOME': str(target / 'cache')}
    (target / 'tmp').mkdir()
    run(['/usr/bin/cargo', 'install', '--locked', '--path', source, '--root', target / 'install'], env=env, timeout=1800)
    binary = target / 'install/bin/topiary'
    if run([binary, '--version']) != 'topiary-cli ' + record['version']:
        raise RuntimeError('Rebuilt Topiary version differs.')
    env.update(TOPIARY_CONFIG_FILE=str(config / 'languages.ncl'), TOPIARY_LANGUAGE_DIR=str(config / 'languages'))
    run([binary, '-C', config / 'languages.ncl', 'prefetch', 'nu'], env=env, timeout=600)
    grammar = target / 'cache/topiary/nu' / record['grammar_revision'] / 'grammar.so'
    if not grammar.is_file():
        raise RuntimeError('Topiary did not build the pinned Nu grammar.')
    (target / 'bin').mkdir()
    shutil.copy2(binary, target / 'bin/topiary')
    (target / 'grammar').mkdir()
    shutil.copy2(grammar, target / 'grammar/nu.so')


def stage_rayfile(record, target):
    if (record['source_url'] != rayfile.SOURCE_URL or record['archive_sha256'] != rayfile.ARCHIVE_SHA256
            or record['binary_sha256'] != rayfile.BINARY_SHA256):
        raise RuntimeError('Unknown Rayfile download pin.')
    target.mkdir()
    archive = target / 'download.tar.gz'
    download(record['source_url'], archive, record['archive_sha256'])
    runtime = target / 'rayfile-runtime'
    runtime.mkdir()
    with tarfile.open(archive, 'r:gz') as stream:
        for name in ('rayfile-c', 'readme.txt'):
            member = stream.getmember('fasttrans/' + name)
            if not member.isfile():
                raise RuntimeError('Unexpected Rayfile archive member.')
            with stream.extractfile(member) as source, (runtime / name).open('xb') as dest:
                shutil.copyfileobj(source, dest)
            (runtime / name).chmod(0o755 if name == 'rayfile-c' else 0o644)
    if sets.digest(runtime / 'rayfile-c') != record['binary_sha256']:
        raise RuntimeError('Rayfile binary checksum mismatch.')
    rayfile.write_json(runtime / 'manifest.json', {'format': 1, **record})
    (runtime / 'SHA256SUMS').write_text(''.join(f'{sets.digest(runtime / name)}  {name}\n' for name in rayfile.RUNTIME_FILES if name != 'SHA256SUMS'), encoding='utf-8')
    rayfile.validate_runtime(runtime)
    nvim.cleanup(archive)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('capture', 'check-targets', 'projects', 'editor', 'topiary', 'rayfile'))
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--recipe', type=Path)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--target', type=Path)
    parser.add_argument('--keep-local-workflow', action='store_true')
    parser.add_argument('--project', choices=('scripts', *PROJECTS))
    args = parser.parse_args()
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    for signum in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupted)
    try:
        args.work.mkdir(parents=True, exist_ok=True)
        recipe = sets.read_json(args.recipe) if args.recipe else None
        if recipe is not None and (not isinstance(recipe, dict) or recipe.get('format') != 1):
            raise ValueError('Unsupported download recipe.')
        if args.command == 'capture':
            print(json.dumps(capture(args.home, args.work), sort_keys=True))
        elif args.command == 'check-targets':
            check_targets(args.home, args.work, args.project)
        elif args.command == 'projects':
            stage_projects(recipe, args.home, args.target, args.work, args.keep_local_workflow, args.project)
        elif args.command == 'editor':
            build_editor(recipe, args.config, args.target, args.home)
        elif args.command == 'topiary':
            build_topiary(recipe['topiary'], args.config, args.target)
        else:
            stage_rayfile(recipe['rayfile'], args.target)
        return 0
    except (OSError, ValueError, RuntimeError, KeyError, TypeError, subprocess.SubprocessError, tarfile.TarError) as error:
        print(f'[ERROR] {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('[ERROR] Interrupted; the restore runner will roll back and clean this invocation.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
