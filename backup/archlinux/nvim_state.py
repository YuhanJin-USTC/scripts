#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request


def run(args, **kwargs):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def files_digest(root):
    return {str(path.relative_to(root)): digest(path)
            for path in sorted(root.rglob("*")) if path.is_file()}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def nvim_version(executable, **kwargs):
    lines = run([str(executable), "--version"], **kwargs).splitlines()
    if not lines or not re.fullmatch(r"NVIM v\d+\.\d+\.\d+", lines[0]):
        raise RuntimeError("Neovim must report a stable release version.")
    return lines[0]


def cleanup(path):
    os.environ["CODEX_TEMP_CLEANUP"] = "1"
    shutil.rmtree(path)


def regular_parents(path):
    for parent in [path, *path.parents]:
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise RuntimeError(f"Not a regular directory: {parent}")


def safe_extract(archive, target, links=False):
    # Validate the complete archive before writing any member.
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        names = set()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or str(path) in names:
                raise RuntimeError(f"Unsafe archive member: {member.name}")
            names.add(str(path))
            if not (member.isfile() or member.isdir() or (links and member.issym())):
                raise RuntimeError(f"Unsupported archive member: {member.name}")
        link_names = {PurePosixPath(m.name) for m in members if m.issym()}
        for member in members:
            path = PurePosixPath(member.name)
            if any(parent in link_names for parent in path.parents):
                raise RuntimeError(f"Archive writes through a link: {member.name}")
            if member.issym():
                resolved = (target / member.name).parent / member.linkname
                if Path(member.linkname).is_absolute() or not resolved.resolve().is_relative_to(target.resolve()):
                    raise RuntimeError(f"Unsafe archive link: {member.name}")
        stream.extractall(target, members=members, filter="data")


def github_url(value):
    value = re.sub(r"^git@github\.com:", "https://github.com/", value)
    if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise RuntimeError("Only public GitHub plugin URLs are supported.")
    return value.removesuffix(".git") + ".git"


def validate_manifest(stage):
    manifest = read_json(stage / "manifest.json")
    if not isinstance(manifest, dict) or manifest.get("format") != 1:
        raise RuntimeError("Unsupported Neovim snapshot format.")
    if not isinstance(manifest.get("plugins"), dict) or not isinstance(manifest.get("parsers"), list):
        raise RuntimeError("Invalid Neovim plugin or parser manifest.")
    if not re.fullmatch(r"NVIM v\d+\.\d+\.\d+", manifest["nvim_version"]):
        raise RuntimeError("Neovim snapshot must use a stable release.")
    if manifest["architecture"] not in ("x86_64", "aarch64"):
        raise RuntimeError("Unsupported Neovim snapshot architecture.")
    if files_digest(stage / "config") != manifest["config_sha256"]:
        raise RuntimeError("Neovim configuration checksum mismatch.")
    if digest(stage / "runtime.tar.gz") != manifest["runtime_sha256"]:
        raise RuntimeError("Neovim runtime checksum mismatch.")
    lock = read_json(stage / "config/lazy-lock.json")
    if not lock or set(lock) != set(manifest["plugins"]):
        raise RuntimeError("Neovim snapshot and lockfile disagree.")
    for name, info in manifest["plugins"].items():
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
            raise RuntimeError("Invalid plugin name in snapshot.")
        if not re.fullmatch(r"[0-9a-f]{40}", info["commit"]) or info["commit"] != lock[name]["commit"]:
            raise RuntimeError(f"Invalid locked commit: {name}")
        github_url(info["url"])
    if "lazy.nvim" not in lock or "nvim-treesitter" not in lock:
        raise RuntimeError("Snapshot lacks Lazy or Treesitter.")
    if not manifest["parsers"] or any(not re.fullmatch(r"[a-z0-9_]+", lang) for lang in manifest["parsers"]):
        raise RuntimeError("Snapshot has no valid Treesitter parser list.")
    return manifest


def download(url, target):
    request = urllib.request.Request(url, headers={"User-Agent": "arch-nvim-backup"})
    with urllib.request.urlopen(request, timeout=120) as response, target.open("wb") as stream:
        shutil.copyfileobj(response, stream)


def backup(archive):
    home = Path.home()
    config = home / ".config/nvim"
    data = home / ".local/share/nvim"
    if not (config / "lazy-lock.json").is_file():
        raise RuntimeError("Neovim lazy-lock.json is missing; open and configure Neovim first.")
    version = nvim_version("nvim")
    arch = platform.machine()
    if arch not in ("x86_64", "aarch64"):
        raise RuntimeError(f"Unsupported architecture: {arch}")
    archive.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix=".nvim-backup-", dir=archive.parent))
    try:
        shutil.copytree(config, temp / "config", symlinks=False)
        lock = read_json(temp / "config/lazy-lock.json")
        plugins = {}
        for name, info in lock.items():
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
                raise RuntimeError("Invalid plugin name in lockfile.")
            repo = data / "lazy" / name
            url = github_url(run(["git", "-C", str(repo), "remote", "get-url", "origin"]))
            plugins[name] = {"url": url, "commit": info["commit"]}
            head = run(["git", "-C", str(repo), "rev-parse", "HEAD"])
            changed = run(["git", "-C", str(repo), "status", "--porcelain"])
            if head != info["commit"] or changed:
                print(f"[WARN] {name} differs locally; the snapshot will restore its locked commit.")
        parsers = sorted(path.stem for path in (data / "site/parser").glob("*.so"))
        asset_name = f"nvim-linux-{'arm64' if arch == 'aarch64' else arch}.tar.gz"
        tag = version.removeprefix("NVIM ")
        download(f"https://api.github.com/repos/neovim/neovim/releases/tags/{tag}", temp / "release.json")
        assets = read_json(temp / "release.json")["assets"]
        asset = next((entry for entry in assets if entry["name"] == asset_name), None)
        expected_url = f"https://github.com/neovim/neovim/releases/download/{tag}/{asset_name}"
        if not asset or asset["browser_download_url"] != expected_url:
            raise RuntimeError("Official Neovim Linux bundle is unavailable.")
        download(expected_url, temp / "runtime.tar.gz")
        runtime_hash = digest(temp / "runtime.tar.gz")
        if asset.get("digest") and asset["digest"] != "sha256:" + runtime_hash:
            raise RuntimeError("Official Neovim asset checksum mismatch.")
        manifest = {"format": 1, "nvim_version": version, "architecture": arch,
                    "runtime_sha256": runtime_hash, "runtime_url": expected_url,
                    "config_sha256": files_digest(temp / "config"),
                    "plugins": plugins, "parsers": parsers}
        write_json(temp / "manifest.json", manifest)
        validate_manifest(temp)
        with tarfile.open(temp / "nvim.tar.gz", "w:gz", dereference=True) as stream:
            for name in ("manifest.json", "config", "runtime.tar.gz"):
                stream.add(temp / name, arcname=name)
        os.replace(temp / "nvim.tar.gz", archive)
    finally:
        cleanup(temp)
    print(f"[OK] Neovim configuration, locked plugins and runtime recorded in {archive}.")


def stage(archive, target):
    regular_parents(target)
    if any(target.iterdir()):
        raise RuntimeError("Neovim staging directory is not empty.")
    safe_extract(archive, target)
    manifest = validate_manifest(target)
    if manifest["architecture"] != platform.machine():
        raise RuntimeError("This Neovim runtime belongs to a different CPU architecture.")
    runtime = target / "runtime"
    runtime.mkdir()
    safe_extract(target / "runtime.tar.gz", runtime, links=True)
    roots = list(runtime.iterdir())
    if len(roots) != 1 or not (roots[0] / "bin/nvim").is_file():
        raise RuntimeError("Invalid official Neovim runtime layout.")
    roots[0].rename(target / "nvim-runtime")
    bundle = target / "nvim-runtime"
    for path in bundle.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(bundle.resolve()):
            raise RuntimeError(f"Runtime link leaves the bundled directory: {path.relative_to(bundle)}")
    print("[OK] Neovim snapshot checksums and archive paths verified.")


def preserve(path, backup_dir, name):
    regular_parents(path.parent)
    regular_parents(backup_dir)
    backup_dir.mkdir(parents=True, exist_ok=True)
    if path.exists() or path.is_symlink():
        target = backup_dir / name
        if target.exists() or target.is_symlink():
            raise RuntimeError(f"Backup target already exists: {target}")
        shutil.move(str(path), str(target))
        print(f"[OK] Existing {path} moved to {target}.")


def deploy_config(source, target, backup_dir):
    validate_manifest(source)
    regular_parents(target.parent)
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix=".nvim-config-", dir=target.parent))
    try:
        shutil.copytree(source / "config", temp / "config")
        preserve(target, backup_dir, "nvim-config")
        try:
            (temp / "config").rename(target)
        except OSError:
            if (backup_dir / "nvim-config").exists() and not target.exists():
                shutil.move(str(backup_dir / "nvim-config"), str(target))
            raise
    finally:
        cleanup(temp)


def preserve_config(backup_dir):
    home = Path.home()
    regular_parents(backup_dir)
    backup_dir.mkdir(parents=True, exist_ok=True)
    for source, name in ((home / ".config/nvim", "nvim-live-config"),
                         (home / "dot_files/nvim/.config/nvim", "nvim-repo-config")):
        if source.is_dir():
            shutil.copytree(source, backup_dir / name, symlinks=False)
    preserve(home / ".config/nvim", backup_dir, "nvim-live-layout")


def check_runtime(source):
    manifest = validate_manifest(source)
    runtime_source = source / "nvim-runtime"
    env = os.environ.copy()
    env["VIMRUNTIME"] = str(runtime_source / "share/nvim/runtime")
    version = nvim_version(runtime_source / "bin/nvim", env=env)
    if version != manifest["nvim_version"]:
        raise RuntimeError("The bundled Neovim binary does not match its manifest.")
    return manifest, version, env


def restore(source, lua_helper):
    manifest, version, env = check_runtime(source)
    home = Path.home()
    config = home / "dot_files/nvim/.config/nvim"
    if files_digest(config) != manifest["config_sha256"]:
        raise RuntimeError("Deployed Neovim configuration differs from snapshot.")
    runtime_source = source / "nvim-runtime"
    data = home / ".local/share/nvim"
    runtime = home / ".local/share/nvim-runtime"
    wrapper = home / ".local/bin/nvim"
    for parent in (data, runtime.parent, wrapper.parent):
        regular_parents(parent)
        parent.mkdir(parents=True, exist_ok=True)
    backup_dir = Path(tempfile.mkdtemp(prefix="nvim_restore_backup_", dir=home))
    print(f"[OK] Neovim safety backup: {backup_dir}", flush=True)
    # Preserve complete old trees, including local edits and extra plugins.
    for path, name in ((data / "lazy", "lazy"), (data / "site", "site"),
                       (runtime, "nvim-runtime"), (wrapper, "nvim")):
        preserve(path, backup_dir, name)
    shutil.copytree(runtime_source, runtime, symlinks=True)
    wrapper.write_text("#!/usr/bin/env bash\n" +
                       "export VIMRUNTIME=" + shlex.quote(str(runtime / "share/nvim/runtime")) + "\n" +
                       "exec " + shlex.quote(str(runtime / "bin/nvim")) + ' "$@"\n', encoding="utf-8")
    wrapper.chmod(0o755)
    env["VIMRUNTIME"] = str(runtime / "share/nvim/runtime")
    env["PATH"] = str(wrapper.parent) + os.pathsep + env.get("PATH", "")
    # Fresh repositories prevent old local changes from leaking into restore.
    (data / "lazy").mkdir()
    for name, info in sorted(manifest["plugins"].items()):
        repo = data / "lazy" / name
        print(f"  -> Restoring {name} at {info['commit'][:12]}...", flush=True)
        run(["git", "clone", "--filter=blob:none", "--no-checkout", "--", info["url"], str(repo)], env=env)
        run(["git", "-C", str(repo), "checkout", "--detach", info["commit"]], env=env)
    for mode in ("build", "verify"):
        subprocess.run([str(runtime / "bin/nvim"), "--headless", "-u", "NONE", "-i", "NONE", "-n",
                        "-l", str(lua_helper), mode, str(config), str(data), str(source / "manifest.json")],
                       env=env, check=True)
    for name, info in manifest["plugins"].items():
        if run(["git", "-C", str(data / "lazy" / name), "rev-parse", "HEAD"]) != info["commit"]:
            raise RuntimeError(f"Plugin did not retain its locked version: {name}")
    if files_digest(config) != manifest["config_sha256"]:
        raise RuntimeError("Neovim configuration or lockfile changed during restore.")
    print(f"[OK] {version}; locked plugins and Treesitter parsers restored.")


def main():
    parser = argparse.ArgumentParser(description="Snapshot and restore the locked Neovim environment.")
    commands = parser.add_subparsers(dest="command", required=True)
    cmd = commands.add_parser("backup")
    cmd.add_argument("archive", type=Path)
    cmd = commands.add_parser("stage")
    cmd.add_argument("archive", type=Path)
    cmd.add_argument("target", type=Path)
    cmd = commands.add_parser("config")
    cmd.add_argument("source", type=Path)
    cmd.add_argument("target", type=Path)
    cmd.add_argument("backup_dir", type=Path)
    cmd = commands.add_parser("restore")
    cmd.add_argument("source", type=Path)
    cmd.add_argument("lua_helper", type=Path)
    cmd = commands.add_parser("preserve-config")
    cmd.add_argument("backup_dir", type=Path)
    cmd = commands.add_parser("check-runtime")
    cmd.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "backup":
            backup(args.archive)
        elif args.command == "stage":
            stage(args.archive, args.target)
        elif args.command == "config":
            deploy_config(args.source, args.target, args.backup_dir)
        elif args.command == "preserve-config":
            preserve_config(args.backup_dir)
        elif args.command == "check-runtime":
            check_runtime(args.source)
        else:
            restore(args.source, args.lua_helper)
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
