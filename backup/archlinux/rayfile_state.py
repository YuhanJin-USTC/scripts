#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile


SOURCE_URL = "https://wuzh01.hpccube.com:65015/efile/share/fasttrans-client.tar.gz"
ARCHIVE_SHA256 = "ef4592c4701073b96e166f533364cb049be7e1ebbd093254fcac4ce4847140f2"
BINARY_SHA256 = "f718db7def476df9cdb259e0424b54bb0d0f82ed864adb84c62730b73d01b0a7"
VERSION = "6.7.8.12"
RUNTIME_FILES = ("rayfile-c", "readme.txt", "manifest.json", "SHA256SUMS")
SNAPSHOT_FILES = {"manifest.json", "launcher"} | {"rayfile-runtime/" + name for name in RUNTIME_FILES}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def cleanup(path):
    os.environ["CODEX_TEMP_CLEANUP"] = "1"
    shutil.rmtree(path)


def regular_parents(path):
    for parent in (path, *path.parents):
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise RuntimeError(f"Not a regular directory: {parent}")


def regular_file(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f"Not a regular file: {path}")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def launcher_text(home):
    executable = home / ".local/share/rayfile-runtime/rayfile-c"
    return '#!/usr/bin/env bash\nexec ' + shlex.quote(str(executable)) + ' "$@"\n'


def validate_runtime(runtime):
    regular_parents(runtime)
    if {p.name for p in runtime.iterdir()} != set(RUNTIME_FILES):
        raise RuntimeError("Unexpected Rayfile runtime contents; keep transfer state outside the snapshot.")
    for name in RUNTIME_FILES:
        regular_file(runtime / name)
    manifest = json.loads((runtime / "manifest.json").read_text(encoding="utf-8"))
    if (not isinstance(manifest, dict) or manifest.get("format") != 1 or manifest.get("architecture") != "x86_64"
            or manifest.get("source_url") != SOURCE_URL
            or not re.fullmatch(r"\d+(?:\.\d+){3}", manifest.get("version", ""))
            or not re.fullmatch(r"[0-9a-f]{64}", manifest.get("archive_sha256", ""))):
        raise RuntimeError("Invalid Rayfile runtime manifest.")
    if digest(runtime / "rayfile-c") != manifest.get("binary_sha256"):
        raise RuntimeError("Rayfile binary checksum mismatch.")
    expected = "".join(f"{digest(runtime / name)}  {name}\n"
                       for name in RUNTIME_FILES if name != "SHA256SUMS")
    if (runtime / "SHA256SUMS").read_text(encoding="utf-8") != expected:
        raise RuntimeError("Rayfile runtime checksums differ.")
    return manifest


def check_runtime(runtime):
    manifest = validate_runtime(runtime)
    if platform.system() != "Linux" or platform.machine() != manifest["architecture"]:
        raise RuntimeError("This Rayfile snapshot requires Linux x86_64.")
    # Version mode exits before logging or connecting.
    result = subprocess.run([str(runtime / "rayfile-c"), "--version"], cwd=runtime,
                            text=True, capture_output=True, timeout=15)
    if result.returncode or result.stdout.strip() != manifest["version"]:
        raise RuntimeError("Rayfile version check failed; verify the system runtime libraries.")
    return manifest


def validate_snapshot(source):
    regular_parents(source)
    if {p.name for p in source.iterdir()} != {"manifest.json", "launcher", "rayfile-runtime"}:
        raise RuntimeError("Unexpected Rayfile snapshot contents.")
    for name in ("manifest.json", "launcher"):
        regular_file(source / name)
    manifest = json.loads((source / "manifest.json").read_text(encoding="utf-8"))
    runtime = validate_runtime(source / "rayfile-runtime")
    expected = {name: digest(source / name) for name in sorted(SNAPSHOT_FILES - {"manifest.json"})}
    if (not isinstance(manifest, dict) or manifest.get("format") != 1 or manifest.get("architecture") != runtime["architecture"]
            or manifest.get("version") != runtime["version"] or manifest.get("files_sha256") != expected):
        raise RuntimeError("Rayfile snapshot checksums or metadata differ.")
    source_home = Path(manifest.get("source_home", ""))
    if not source_home.is_absolute() or (source / "launcher").read_text(encoding="utf-8") != launcher_text(source_home):
        raise RuntimeError("Unrecognized Rayfile launcher; refusing to restore arbitrary commands.")
    return manifest


def backup(archive, home):
    runtime = home / ".local/share/rayfile-runtime"
    launcher = home / ".local/bin/rayfile-c"
    if not any(p.exists() or p.is_symlink() for p in (runtime, launcher)):
        if archive.exists() or archive.is_symlink():
            raise RuntimeError("Rayfile is absent but an older snapshot exists; review it before backing up.")
        print("[SKIP] Rayfile is not installed; no snapshot created.")
        return
    manifest = check_runtime(runtime)
    regular_parents(launcher.parent)
    regular_file(launcher)
    if launcher.read_text(encoding="utf-8") != launcher_text(home):
        raise RuntimeError("Rayfile launcher differs from the managed entry point.")
    regular_parents(archive.parent)
    if archive.exists() or archive.is_symlink():
        regular_file(archive)
    archive.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix=".rayfile-backup-", dir=archive.parent))
    try:
        source = temp / "input"
        source.mkdir()
        shutil.copytree(runtime, source / "rayfile-runtime")
        shutil.copy2(launcher, source / "launcher")
        write_json(source / "manifest.json", {
            "format": 1, "architecture": manifest["architecture"], "version": manifest["version"],
            "source_home": str(home),
            "files_sha256": {name: digest(source / name)
                             for name in sorted(SNAPSHOT_FILES - {"manifest.json"})},
        })
        validate_snapshot(source)
        with tarfile.open(temp / "rayfile.tar.gz", "w:gz") as stream:
            for name in sorted(SNAPSHOT_FILES):
                stream.add(source / name, arcname=name, recursive=False)
        os.replace(temp / "rayfile.tar.gz", archive)
    finally:
        cleanup(temp)
    print(f"[OK] Rayfile {manifest['version']} and launcher recorded in {archive}.")


def stage(archive, target):
    regular_file(archive)
    regular_parents(target)
    if not target.is_dir() or any(target.iterdir()):
        raise RuntimeError("Rayfile staging requires an existing empty directory.")
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        names = [m.name for m in members]
        if (len(names) != len(set(names)) or set(names) != SNAPSHOT_FILES
                or any(not m.isfile() or m.size > 256 * 1024 * 1024 for m in members)):
            raise RuntimeError("Unsafe or unexpected Rayfile archive members.")
        stream.extractall(target, members=members, filter="data")
    manifest = validate_snapshot(target)
    if platform.system() != "Linux" or platform.machine() != manifest["architecture"]:
        raise RuntimeError("This Rayfile snapshot requires Linux x86_64.")
    for name in SNAPSHOT_FILES:
        (target / name).chmod(0o755 if name in ("launcher", "rayfile-runtime/rayfile-c") else 0o644)
    print("[OK] Rayfile snapshot paths, architecture and checksums verified.")


def deploy(source, home, replace):
    manifest = check_runtime(source / "rayfile-runtime")
    runtime = home / ".local/share/rayfile-runtime"
    launcher = home / ".local/bin/rayfile-c"
    for parent in (home, runtime.parent, launcher.parent):
        regular_parents(parent)
    targets = ((runtime, "rayfile-runtime"), (launcher, "launcher"))
    if not replace and any(p.exists() or p.is_symlink() for p, _ in targets):
        raise RuntimeError("Rayfile is already installed; use a reviewed snapshot restore to replace it.")
    runtime.parent.mkdir(parents=True, exist_ok=True)
    launcher.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix=".rayfile-deploy-", dir=home))
    saved, deployed = [], []
    keep_temp = False
    try:
        shutil.copytree(source / "rayfile-runtime", temp / "rayfile-runtime")
        (temp / "launcher").write_text(launcher_text(home), encoding="utf-8")
        (temp / "launcher").chmod(0o755)
        backup_dir = None
        if any(p.exists() or p.is_symlink() for p, _ in targets):
            backup_dir = Path(tempfile.mkdtemp(prefix="rayfile_restore_backup_", dir=home))
            print(f"[OK] Rayfile safety backup: {backup_dir}")
        try:
            for target, name in targets:
                if target.exists() or target.is_symlink():
                    target.rename(backup_dir / name)
                    saved.append((target, backup_dir / name))
            for target, name in targets:
                (temp / name).rename(target)
                deployed.append((target, name))
            check_runtime(runtime)
        except Exception:
            try:
                for target, name in reversed(deployed):
                    target.rename(temp / name)
                for target, previous in reversed(saved):
                    previous.rename(target)
            except OSError:
                keep_temp = True
                print(f"[ERROR] Rollback incomplete; retain {temp} and {backup_dir}.", file=sys.stderr)
            raise
    finally:
        if not keep_temp:
            cleanup(temp)
    print(f"[OK] Rayfile {manifest['version']} installed at {runtime}; transfer state retained.")


def install(archive, home):
    regular_file(archive)
    if digest(archive) != ARCHIVE_SHA256:
        raise RuntimeError("Official archive differs from the reviewed download; review the new release first.")
    temp = Path(tempfile.mkdtemp(prefix="rayfile-install-"))
    try:
        runtime = temp / "rayfile-runtime"
        runtime.mkdir()
        with tarfile.open(archive, "r:gz") as stream:
            for name in ("rayfile-c", "readme.txt"):
                member = stream.getmember("fasttrans/" + name)
                if not member.isfile():
                    raise RuntimeError("Invalid official Rayfile member.")
                with stream.extractfile(member) as src, (runtime / name).open("xb") as dst:
                    shutil.copyfileobj(src, dst)
                (runtime / name).chmod(0o755 if name == "rayfile-c" else 0o644)
        write_json(runtime / "manifest.json", {
            "format": 1, "architecture": "x86_64", "version": VERSION,
            "source_url": SOURCE_URL, "archive_sha256": ARCHIVE_SHA256, "binary_sha256": BINARY_SHA256,
        })
        (runtime / "SHA256SUMS").write_text(
            "".join(f"{digest(runtime / name)}  {name}\n" for name in RUNTIME_FILES if name != "SHA256SUMS"),
            encoding="utf-8")
        deploy(temp, home, replace=False)
    finally:
        cleanup(temp)


def main():
    parser = argparse.ArgumentParser(description="Install, snapshot and restore the locked Rayfile client.")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("install", "backup", "restore", "verify"):
        cmd = commands.add_parser(name)
        if name != "verify":
            cmd.add_argument("source" if name == "restore" else "archive", type=Path)
        cmd.add_argument("--home", type=Path, default=Path.home())
    cmd = commands.add_parser("stage")
    cmd.add_argument("archive", type=Path)
    cmd.add_argument("target", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "stage":
            stage(args.archive.absolute(), args.target.absolute())
        else:
            home = args.home.absolute()
            regular_parents(home)
            if args.command == "install":
                install(args.archive.absolute(), home)
            elif args.command == "backup":
                backup(args.archive.absolute(), home)
            elif args.command == "restore":
                validate_snapshot(args.source.absolute())
                deploy(args.source.absolute(), home, replace=True)
            else:
                manifest = check_runtime(home / ".local/share/rayfile-runtime")
                launcher = home / ".local/bin/rayfile-c"
                regular_parents(launcher.parent)
                regular_file(launcher)
                if launcher.read_text(encoding="utf-8") != launcher_text(home):
                    raise RuntimeError("Rayfile launcher differs from the managed entry point.")
                print(f"[OK] Rayfile {manifest['version']}: runtime and launcher verified.")
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, EOFError,
            tarfile.TarError, subprocess.SubprocessError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
