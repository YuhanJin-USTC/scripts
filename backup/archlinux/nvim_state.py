#!/usr/bin/env python3

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import uuid


NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]*")
COMMIT = re.compile(r"[0-9a-f]{40}")
HELPER = Path(__file__).with_name("nvim_plugins.lua")
MIN_FREE = 2 * 1024 ** 3
CORE_ARCH_PACKAGES = ("python-pynvim", "ipython", "python-matplotlib", "python-pylatexenc")
FORMATTER_LINTER_TOOLS = ("isort", "black", "shfmt", "markdownlint", "clang-tidy", "pylint")


class NeedsRebuild(RuntimeError):
    pass


def run(args, **kwargs):
    result = subprocess.run([str(a) for a in args], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=kwargs.pop("timeout", 900), **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(args[0]).name} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout.strip()


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def files_digest(root, preserve_links=False):
    if not root.is_dir():
        raise RuntimeError(f"Missing directory: {root}")
    result = {}
    for parent, dirs, files in os.walk(root, followlinks=not preserve_links):
        parent = Path(parent)
        real = parent.resolve()
        ancestors = [item.resolve() for item in parent.parents if item == root or item.is_relative_to(root)]
        if real in ancestors:
            raise RuntimeError(f"Directory symlink cycle: {parent}")
        if preserve_links:
            for name in sorted(dirs + files):
                path = parent / name
                if path.is_symlink():
                    target = os.readlink(path)
                    if not path.exists() or Path(target).is_absolute() or not path.resolve().is_relative_to(root.resolve()):
                        raise RuntimeError(f"Non-portable payload symlink: {path}")
                    result[path.relative_to(root).as_posix()] = {"symlink": target}
            dirs[:] = [name for name in dirs if not (parent / name).is_symlink()]
        for name in sorted(files):
            path = parent / name
            if preserve_links and path.is_symlink():
                continue
            if not path.is_file():
                raise RuntimeError(f"Unsupported file: {path}")
            result[path.relative_to(root).as_posix()] = digest(path)
    return dict(sorted(result.items()))


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def atomic_json(path, value):
    temp = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        write_json(temp, value)
        with temp.open("rb") as stream:
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            cleanup(temp)


def cleanup(path):
    os.environ["CODEX_TEMP_CLEANUP"] = "1"
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def regular_parents(path):
    for parent in [path, *path.parents]:
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise RuntimeError(f"Not a regular directory: {parent}")


def nvim_version(executable, candidate=None, home=None, **kwargs):
    output = helper_run(candidate, home, "version", sandbox=True) if candidate else run([executable, "--version"], **kwargs)
    lines = output.splitlines()
    if not lines or not re.fullmatch(r"NVIM v\d+\.\d+\.\d+", lines[0]):
        raise RuntimeError("Neovim must report a stable release version.")
    return lines[0]


def github_url(value):
    value = re.sub(r"^git@github\.com:", "https://github.com/", value)
    if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise RuntimeError("Only public GitHub plugin URLs are supported.")
    return value.removesuffix(".git") + ".git"


def safe_extract(archive, target):
    regular_parents(target)
    if target.exists() and any(target.iterdir()):
        raise RuntimeError(f"Extraction target is not empty: {target}")
    with tarfile.open(archive, "r:gz") as stream:
        members = stream.getmembers()
        names = set()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or str(path) in names or str(path) in ("", "."):
                raise RuntimeError(f"Unsafe archive member: {member.name}")
            names.add(str(path))
            if not (member.isfile() or member.isdir() or member.issym()):
                raise RuntimeError(f"Unsupported archive member: {member.name}")
        links = {tuple(PurePosixPath(m.name).parts): PurePosixPath(m.linkname).parts
                 for m in members if m.issym()}
        files = {PurePosixPath(m.name) for m in members if not m.isdir()}
        namespace = {()}
        for member in members:
            member_path = PurePosixPath(member.name)
            namespace.add(tuple(member_path.parts))
            namespace.update(tuple(parent.parts) for parent in member_path.parents)
        for member in members:
            path = PurePosixPath(member.name)
            if any(parent in files for parent in path.parents):
                raise RuntimeError(f"Archive writes through a file or link: {member.name}")
            if member.issym():
                if PurePosixPath(member.linkname).is_absolute():
                    raise RuntimeError(f"Unsafe archive link: {member.name}")
                pending = list(path.parent.parts + PurePosixPath(member.linkname).parts)
                resolved = []
                expansions = 0
                while pending:
                    part = pending.pop(0)
                    if part == ".":
                        continue
                    if part == "..":
                        if not resolved:
                            raise RuntimeError(f"Archive link escapes target: {member.name}")
                        resolved.pop()
                        continue
                    resolved.append(part)
                    link = links.get(tuple(resolved))
                    if link is not None:
                        expansions += 1
                        if expansions > len(links) + 40:
                            raise RuntimeError(f"Archive symlink cycle: {member.name}")
                        if link and link[0] == "/":
                            raise RuntimeError(f"Unsafe chained archive link: {member.name}")
                        resolved.pop()
                        pending = list(link) + pending
                if tuple(resolved) not in namespace:
                    raise RuntimeError(f"Archive link target is missing: {member.name}")
        required = sum(m.size for m in members if m.isfile())
        existing = target
        while not existing.exists():
            existing = existing.parent
        if shutil.disk_usage(existing).free < required + 64 * 1024 ** 2:
            raise RuntimeError("Insufficient free space for archive extraction.")
        target.mkdir(parents=True, exist_ok=True)
        stream.extractall(target, members=members, filter="data")
        for member in members:
            if member.issym() and (not (target / member.name).exists() or not (target / member.name).resolve().is_relative_to(target.resolve())):
                raise RuntimeError(f"Extracted link leaves target: {member.name}")


def tree_copy(source, target, preserve_links=False):
    shutil.copytree(source, target, symlinks=preserve_links)


def check_plugin_checkout(repo):
    directory = repo / ".git"
    if not repo.is_dir() or repo.is_symlink() or not directory.is_dir() or directory.is_symlink():
        raise RuntimeError(f"Plugin needs its complete local .git directory: {repo.name}")


def read_head(repo):
    check_plugin_checkout(repo)
    directory = repo / ".git"
    value = (directory / "HEAD").read_text(encoding="utf-8").strip()
    if value.startswith("ref: "):
        ref = value[5:]
        if not ref.startswith("refs/") or ".." in PurePosixPath(ref).parts:
            raise RuntimeError(f"Invalid Git reference: {repo.name}")
        path = directory / ref
        if path.is_file():
            value = path.read_text(encoding="utf-8").strip()
        else:
            packed = directory / "packed-refs"
            rows = packed.read_text(encoding="utf-8").splitlines() if packed.exists() else []
            value = next((row.split(" ", 1)[0] for row in rows if row.endswith(" " + ref)), "")
    if not COMMIT.fullmatch(value):
        raise RuntimeError(f"Unresolved plugin HEAD: {repo.name}")
    return value


def root_for(home):
    return home / ".local/share/nvim-runtime"


def generation(root, name):
    if not NAME.fullmatch(name):
        raise RuntimeError("Invalid generation ID.")
    path = root / "generations" / name
    regular_parents(path)
    if not path.is_dir():
        raise RuntimeError(f"Unknown generation: {name}")
    return path


def active_id(root):
    path = root / "active"
    if not path.exists() and not path.is_symlink():
        return None
    if not path.is_symlink():
        raise RuntimeError("Managed active must be a symlink.")
    value = os.readlink(path)
    match = re.fullmatch(r"generations/([A-Za-z0-9][A-Za-z0-9_.-]*)", value)
    if not match or not (root / value).is_dir():
        raise RuntimeError("Invalid or missing active generation.")
    return match[1]


@contextmanager
def locked(root):
    regular_parents(root)
    root.mkdir(parents=True, exist_ok=True)
    path = root / ".lifecycle.lock"
    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW
    fd = os.open(path, flags, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another Neovim lifecycle operation is running.") from None
        yield
    finally:
        os.close(fd)


def new_generation(root, name=None, retry=False, reuse_candidate=False):
    parent = root / "generations"
    regular_parents(parent)
    parent.mkdir(exist_ok=True)
    if shutil.disk_usage(parent).free < MIN_FREE:
        raise RuntimeError("At least 2 GiB free space is required before preparation.")
    name = name or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8]
    if not NAME.fullmatch(name):
        raise RuntimeError("Invalid generation ID.")
    path = parent / name
    if path.exists():
        regular_parents(path)
        previous = read_json(path / "manifest.json")
        if not retry or active_id(root) == name or (previous.get("status") != "failed" and not (reuse_candidate and previous.get("status") == "validated")):
            raise RuntimeError("Retry requires an inactive failed candidate; an inactive validated candidate also needs --reuse-candidate.")
        allowed = {"config", "data", "runtime", "state", "cache", "logs", "release.json",
                   "manifest.json", "runtime.tar.gz", ".runtime-unpack", "plugin-edit-review", "attempts"}
        if any(item.name not in allowed or item.is_symlink() for item in path.iterdir()):
            raise RuntimeError("Unexpected candidate files; refusing retry relocation.")
        attempts = path / "attempts"
        regular_parents(attempts)
        saved = attempts / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8])
        saved.mkdir(parents=True)
        for item in list(path.iterdir()):
            if item.name != "attempts":
                item.rename(saved / item.name)
    else:
        path.mkdir()
    (path / "logs").mkdir()
    return path


def candidate_env(path, home):
    env = os.environ.copy()
    env["NVIM_EXTERNAL_CACHE_HOME"] = env.get("NVIM_EXTERNAL_CACHE_HOME") or env.get("XDG_CACHE_HOME") or str(home / ".cache")
    for key in ("NVIM_APPNAME", "NVIM", "NVIM_LISTEN_ADDRESS", "VIMINIT", "EXINIT", "LUA_INIT", "LUA_PATH", "LUA_CPATH"):
        env.pop(key, None)
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(path / "config"), XDG_DATA_HOME=str(path / "data"),
               XDG_STATE_HOME=str(path / "state"), XDG_CACHE_HOME=str(path / "cache"),
               NVIM_MANAGED_GENERATION=path.name, VIMRUNTIME=str(path / "runtime/share/nvim/runtime"))
    mason = home / ".local/share/nvim/mason/bin"
    env["PATH"] = str(mason) + os.pathsep + env.get("PATH", "")
    return env


INTERACTION_CHECK = r'''import json, sys, time
from pathlib import Path
import pynvim
root=Path(sys.argv[1])
n=pynvim.attach('child',argv=[str(root/'runtime/bin/nvim'),'--embed','--headless','-u',str(root/'config/nvim/init.lua'),'-i','NONE','-n'])
def lua(code):return n.exec_lua(code)
def wait(check,message,timeout=12):
 end=time.monotonic()+timeout
 while time.monotonic()<end:
  if check():return
  time.sleep(0.04)
 raise RuntimeError(message)
def normal():
 n.input('\x1b');wait(lambda:n.api.get_mode()['mode']=='n','Could not enter normal mode')
def visible_text():
 return lua("""local texts = {}; local ns=vim.api.nvim_get_namespaces()['render-markdown.nvim'];
 for _,m in ipairs(vim.api.nvim_buf_get_extmarks(0,ns,0,-1,{details=true})) do
   for _,v in ipairs(m[4].virt_text or {}) do texts[#texts+1]=v[1] end
   for _,line in ipairs(m[4].virt_lines or {}) do for _,v in ipairs(line) do texts[#texts+1]=v[1] end end
 end; return table.concat(texts,' ')""")
try:
 lua("require('lazy').load {plugins=vim.tbl_keys(require('lazy.core.config').plugins),wait=true}")
 lua(r"""local b=vim.api.nvim_create_buf(true,false); vim.api.nvim_set_current_buf(b);
 vim.api.nvim_buf_set_lines(b,0,-1,false,{'# Review','','text','',[[$\alpha + \beta$]],'', '$$', [[\gamma = 2]], '$$', '', 'end'});
 vim.bo[b].filetype='markdown'; vim.api.nvim_win_set_cursor(0,{11,0});
 vim.treesitter.get_parser(b):parse(); require('render-markdown').render {buf=b}""")
 wait(lambda:all(c in visible_text() for c in ('α','β','γ')),'Markdown formulas did not produce Unicode extmarks')
 n.input('i');wait(lambda:n.api.get_mode()['mode'].startswith('i'),'Insert mode did not start')
 wait(lambda:visible_text()=='','Markdown remained rendered in insert mode')
 normal();wait(lambda:'α' in visible_text(),'Markdown did not render again in normal mode')
 n.input(' tm');wait(lambda:lua("return require('render-markdown').get()") is False,'Markdown toggle did not disable')
 wait(lambda:visible_text()=='','Disabled Markdown retained render marks')
 n.input(' tm');wait(lambda:'α' in visible_text(),'Markdown toggle did not restore formulas')
 def completion():
  normal();lua("require('blink.cmp').hide(); local b=vim.api.nvim_create_buf(true,false); vim.api.nvim_set_current_buf(b); vim.api.nvim_buf_set_lines(b,0,-1,false,{'alphareview alpsreview','alp'}); vim.api.nvim_win_set_cursor(0,{2,2})")
  n.input('A');wait(lambda:n.api.get_mode()['mode'].startswith('i'),'Completion buffer not in insert mode')
 completion();n.input('\x10')
 wait(lambda:lua("return require('blink.cmp').is_menu_visible()"),'Ctrl-p failed to open completion')
 wait(lambda:len(lua("return require('blink.cmp').get_items()"))>=2,'Buffer completion items are missing')
 first=lua("return require('blink.cmp').get_items()[1].label")
 assert lua("return require('blink.cmp').get_selected_item()") is None
 n.input('\r');wait(lambda:n.current.line==first,'Enter failed to accept the first item')
 completion();n.input('\x0e');wait(lambda:lua("return require('blink.cmp').is_menu_visible()"),'Ctrl-n failed to open completion')
 n.input('\x19');time.sleep(0.15)
 assert n.current.line not in ('alphareview','alpsreview'),'Ctrl-y accepted an unselected item'
 completion();n.input('\x0e');wait(lambda:len(lua("return require('blink.cmp').get_items()"))>=2,'Completion did not reopen')
 n.input('\x0a');wait(lambda:lua("return require('blink.cmp').get_selected_item_idx()") == 1,'Ctrl-j did not select first')
 n.input('\x0a');wait(lambda:lua("return require('blink.cmp').get_selected_item_idx()") == 2,'Ctrl-j did not select next')
 n.input('\x0b');wait(lambda:lua("return require('blink.cmp').get_selected_item_idx()") == 1,'Ctrl-k did not select previous')
 selected=lua("return require('blink.cmp').get_selected_item().label")
 n.input('\x19');wait(lambda:n.current.line==selected,'Ctrl-y failed on a selected item')
 normal()
 assert lua('return vim.v.errmsg')=='',lua('return vim.v.errmsg')
 print(json.dumps({'passed':True,'level':'real-embedded-key-input','markdown_formula_extmarks':'passed','normal_insert_modes':'passed','markdown_toggle':'passed','blink_enter_first':'passed','blink_ctrl_n_p_open':'passed','blink_ctrl_j_k_selection':'passed','blink_ctrl_y_selection_guard':'passed'}))
finally:
 try:n.command('qa!')
 except (EOFError,OSError):pass
 n.close()
'''

def helper_run(path, home, mode, helper=HELPER, sandbox=False, initialize=False):
    env = candidate_env(path, home)
    command = [str(path / "runtime/bin/nvim"), "--headless", "-u", "NONE", "-i", "NONE", "-n",
               "-l", str(helper), mode, str(path / "config/nvim"), str(path / "data/nvim"),
               str(path / "manifest.json")]
    if mode == "interaction":
        command = ["/usr/bin/python3", "-B", "-c", INTERACTION_CHECK, str(path)]
    elif mode == "version":
        command = [str(path / "runtime/bin/nvim"), "--version"]
    if not sandbox:
        return run(command, env=env, timeout=1800)
    if not shutil.which("bwrap"):
        raise RuntimeError("Offline validation requires bubblewrap (bwrap).")
    temp = Path(tempfile.mkdtemp(prefix="nvim-verify-"))
    try:
        for name in ("home", "state", "cache", "tmp", "runtime", "matplotlib", "ipython"):
            (temp / name).mkdir()
        env.update(HOME=str(temp / "home"), XDG_STATE_HOME=str(temp / "state"),
                   XDG_CACHE_HOME=str(temp / "cache"), TMPDIR=str(temp / "tmp"),
                   XDG_RUNTIME_DIR=str(temp / "runtime"), NVIM_LOG_FILE=str(temp / "nvim.log"),
                   MPLCONFIGDIR=str(temp / "matplotlib"), IPYTHONDIR=str(temp / "ipython"),
                   MPLBACKEND="Agg", PYTHONDONTWRITEBYTECODE="1")
        env = {key: env[key] for key in ("HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME",
               "XDG_CACHE_HOME", "XDG_RUNTIME_DIR", "TMPDIR", "NVIM_LOG_FILE", "NVIM_MANAGED_GENERATION",
               "VIMRUNTIME", "MPLCONFIGDIR", "IPYTHONDIR", "MPLBACKEND", "PYTHONDONTWRITEBYTECODE", "NVIM_EXTERNAL_CACHE_HOME")}
        mason = home / ".local/share/nvim/mason"
        env.update(PATH=str(mason / "bin") + ":/usr/local/bin:/usr/bin:/bin", LANG="C.UTF-8")
        topiary = home / ".config/topiary"
        if topiary.is_dir():
            tree_copy(topiary, temp / "topiary")
            env.update(TOPIARY_CONFIG_FILE=str(temp / "topiary/languages.ncl"), TOPIARY_LANGUAGE_DIR=str(temp / "topiary/languages"))
        writable = []
        if mode in ("startup", "interaction"):
            if initialize:
                writable = ["--bind", str(path / "data"), str(path / "data")]
            else:
                tree_copy(path / "data", temp / "data", preserve_links=True)
                writable = ["--bind", str(temp / "data"), str(path / "data")]
        command_prefix = ["bwrap", "--die-with-parent", "--unshare-net", "--unshare-pid", "--unshare-ipc",
                          "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc"]
        for hidden in ("/home", "/root", "/mnt", "/run", "/tmp"):
            command_prefix += ["--tmpfs", hidden]
        command_prefix += ["--ro-bind", str(path), str(path), "--ro-bind", str(helper), str(helper),
                           "--bind", str(temp), str(temp)]
        if mason.is_dir():
            command_prefix += ["--ro-bind", str(mason), str(mason)]
        topiary_cache = Path(env["NVIM_EXTERNAL_CACHE_HOME"]) / "topiary"
        if topiary_cache.is_dir():
            command_prefix += ["--ro-bind", str(topiary_cache), str(topiary_cache)]
        command = command_prefix + writable + [
                   "--chdir", str(temp / "home"), "--"] + command
        return run(command, env=env, timeout=180)
    finally:
        cleanup(temp)


def payload_hashes(path):
    return {name: files_digest(path / relative, preserve_links=name in ("plugins", "runtime")) for name, relative in
            (("config", "config/nvim"), ("runtime", "runtime"),
             ("plugins", "data/nvim/lazy"), ("site", "data/nvim/site"))}


def payload_executables(path, staged=False):
    result = {}
    layout = (("config", "config"), ("runtime", "runtime"), ("plugins", "plugins"), ("site", "site")) if staged else (
        ("config", "config/nvim"), ("runtime", "runtime"), ("plugins", "data/nvim/lazy"), ("site", "data/nvim/site"))
    for name, relative in layout:
        root = path / relative
        executable = {}
        for parent, _, files in os.walk(root, followlinks=False):
            for entry in files:
                item = Path(parent) / entry
                if not item.is_symlink() and item.is_file() and item.stat().st_mode & 0o111:
                    executable[item.relative_to(root).as_posix()] = item.stat().st_mode & 0o111
        result[name] = executable
    return result


def content_identity(manifest):
    fields = ("format", "architecture", "nvim_version", "runtime_source", "payload_sha256",
              "payload_executables", "source_policy", "source", "local_source_at_import",
              "selection_specs", "plugins", "parsers", "grammars", "external_tools")
    stable = {key: manifest.get(key) for key in fields}
    return hashlib.sha256(json.dumps(stable, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def check_payload(path, manifest):
    if manifest.get("format") != 2 or manifest.get("architecture") != platform.machine():
        raise RuntimeError("Unsupported generation format or CPU architecture.")
    if not re.fullmatch(r"NVIM v\d+\.\d+\.\d+", manifest.get("nvim_version", "")):
        raise RuntimeError("Invalid runtime version.")
    binary = path / "runtime/bin/nvim"
    if not binary.is_file() or not os.access(binary, os.X_OK) or not binary.resolve().is_relative_to((path / "runtime").resolve()):
        raise RuntimeError("Runtime executable is missing, non-executable or outside its bundle.")
    if payload_hashes(path) != manifest.get("payload_sha256"):
        raise RuntimeError("Generation content changed; prepare a fresh candidate before activation or backup.")
    if "payload_executables" in manifest and payload_executables(path) != manifest["payload_executables"]:
        raise RuntimeError("Generation executable permissions changed.")
    for name, info in manifest["plugins"].items():
        if not NAME.fullmatch(name) or not COMMIT.fullmatch(info["commit"]):
            raise RuntimeError("Invalid plugin manifest.")
        if read_head(path / "data/nvim/lazy" / name) != info["commit"]:
            raise RuntimeError(f"Plugin HEAD differs from manifest: {name}")


def source_state(home):
    source = home / "dot_files/nvim/.config/nvim"
    effective = home / ".config/nvim"
    if not source.is_dir():
        source = effective
    if not source.is_dir():
        raise RuntimeError("Neovim source configuration is missing.")
    if not (source / "lua/plugin_specs.lua").is_file():
        raise RuntimeError("Neovim source lacks the shared plugin_specs.lua contract.")
    return {"path": str(source.resolve()), "sha256": files_digest(source),
            "effective_path": str(effective),
            "effective_sha256": files_digest(effective) if effective.is_dir() else None}


def check_source(home, manifest):
    if manifest.get("source_policy") == "imported":
        if manifest.get("local_source_at_import") != optional_source(home):
            raise RuntimeError("Local configuration changed since import; import again before activation.")
    elif source_state(home) != manifest.get("source"):
        raise RuntimeError("Source configuration or lockfile changed; prepare a fresh candidate.")


def optional_source(home):
    try:
        return source_state(home)
    except RuntimeError:
        paths = (home / "dot_files/nvim/.config/nvim", home / ".config/nvim")
        return {str(p): files_digest(p) if p.is_dir() else None for p in paths}


def download(url, target):
    request = urllib.request.Request(url, headers={"User-Agent": "managed-nvim-lifecycle"})
    with urllib.request.urlopen(request, timeout=120) as response, target.open("xb") as stream:
        shutil.copyfileobj(response, stream)


def acquire_runtime(path, tag=None):
    arch = platform.machine()
    if arch not in ("x86_64", "aarch64"):
        raise RuntimeError("Unsupported CPU architecture.")
    endpoint = "latest" if tag is None else "tags/" + tag
    metadata = path / "release.json"
    download("https://api.github.com/repos/neovim/neovim/releases/" + endpoint, metadata)
    release = read_json(metadata)
    tag = release["tag_name"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag) or release.get("prerelease") or release.get("draft"):
        raise RuntimeError("The runtime source is not a stable release.")
    asset_name = f"nvim-linux-{'arm64' if arch == 'aarch64' else arch}.tar.gz"
    asset = next((item for item in release["assets"] if item["name"] == asset_name), None)
    url = f"https://github.com/neovim/neovim/releases/download/{tag}/{asset_name}"
    if not asset or asset["browser_download_url"] != url:
        raise RuntimeError("Official runtime asset is unavailable.")
    expected = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", expected):
        raise RuntimeError("Official runtime asset lacks its published SHA-256 digest.")
    archive = path / "runtime.tar.gz"
    download(url, archive)
    if "sha256:" + digest(archive) != expected:
        raise RuntimeError("Official runtime checksum mismatch.")
    unpack = path / ".runtime-unpack"
    safe_extract(archive, unpack)
    roots = list(unpack.iterdir())
    if len(roots) != 1 or not (roots[0] / "bin/nvim").is_file() or not (roots[0] / "share/nvim/runtime").is_dir():
        raise RuntimeError("Invalid official runtime layout.")
    roots[0].rename(path / "runtime")
    cleanup(unpack)
    cleanup(archive)
    return {"url": url, "archive_sha256": expected[7:], "tag": tag, "architecture": arch}


def clone_plugin(url, target, ref=None):
    run(["git", "clone", "--filter=blob:none", "--no-checkout", "--", github_url(url), target])
    if ref:
        run(["git", "-C", target, "checkout", "--detach", ref])


def choose_ref(repo, spec):
    if spec.get("commit"):
        return spec["commit"]
    if spec.get("tag"):
        return "refs/tags/" + spec["tag"]
    version = spec.get("version")
    if version:
        if not re.fullmatch(r"(?:\d+\.)?\*", version):
            raise RuntimeError(f"Unsupported version constraint; review explicitly: {version}")
        major = int(version.split(".")[0]) if version != "*" else None
        tags = []
        for tag in run(["git", "-C", repo, "tag", "--list"]).splitlines():
            match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag)
            if match and (major is None or int(match[1]) == major):
                tags.append((tuple(map(int, match.groups())), tag))
        if not tags:
            raise RuntimeError(f"No stable tag satisfies {version}: {repo.name}")
        return "refs/tags/" + max(tags)[1]
    if spec.get("branch"):
        return "refs/remotes/origin/" + spec["branch"]
    return "refs/remotes/origin/HEAD"


def mason_backend():
    import importlib.util
    name = "nvim_managed_mason_tools"
    if name not in sys.modules:
        spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name("mason_tools.py"))
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    return sys.modules[name]


def formatter_linter_tools(home, env_path, mason_records):
    records = {}
    query_env = {**os.environ, "LC_ALL": "C", "PYTHONDONTWRITEBYTECODE": "1"}
    for name in FORMATTER_LINTER_TOOLS:
        resolved = shutil.which(name, path=env_path)
        args = ["--version-number"] if name == "isort" else ["--version"]
        info = {"path": resolved, "realpath": None, "sha256": None, "version": None,
                "version_output": None, "version_args": args, "validation": "unavailable",
                "source": {"manager": "unknown"}, "rebuild": {"method": "unavailable"}}
        if resolved:
            realpath = Path(resolved).resolve()
            info.update(realpath=str(realpath), sha256=digest(realpath))
            try:
                output = run([resolved, *args], timeout=15, env=query_env, cwd="/tmp")
                version = next((line.strip() for line in output.splitlines() if re.search(r"\d+\.\d+", line)), None)
                info.update(version=version, version_output=output,
                            validation="version-only" if version else "version-unknown")
            except (OSError, RuntimeError, subprocess.SubprocessError):
                info["validation"] = "version-unknown"
            mason_packages = home / ".local/share/nvim/mason/packages"
            if realpath.is_relative_to(mason_packages):
                package = realpath.relative_to(mason_packages).parts[0]
                if package in mason_records.get("tools", {}):
                    info["source"] = {"manager": "mason", "package": package,
                                      "record": "mason.tools." + package}
                    info["rebuild"] = {"method": "existing-mason-record", "record": "mason.tools." + package,
                                       "authorization_required": True}
            else:
                try:
                    owner = run(["/usr/bin/pacman", "-Qoq", realpath], env=query_env, timeout=15)
                    if not re.fullmatch(r"[a-z0-9][a-z0-9@._+:-]*", owner):
                        raise RuntimeError("Executable has no single package owner.")
                    installed = run(["/usr/bin/pacman", "-Q", owner], env=query_env, timeout=15).split(maxsplit=1)
                    if len(installed) != 2 or installed[0] != owner:
                        raise RuntimeError("Installed package metadata is incomplete.")
                    info["source"] = {"manager": "pacman", "package": owner, "package_version": installed[1],
                                      "repository": None, "official_repository": False,
                                      "evidence": "canonical executable package ownership and installed package metadata"}
                    metadata = run(["/usr/bin/pacman", "-Si", owner], env=query_env, timeout=15)
                    repository = next((line.partition(":")[2].strip() for line in metadata.splitlines()
                                       if line.partition(":")[0].strip() == "Repository"), None)
                    info["source"].update(repository=repository, official_repository=repository in ("core", "extra", "multilib"))
                    if info["source"]["official_repository"]:
                        info["rebuild"] = {"method": "existing-arch-package-transaction", "packages": [owner],
                                           "version_policy": "record observed version; use a full Arch upgrade/install, never an implicit downgrade",
                                           "authorization_required": True}
                except (OSError, RuntimeError, subprocess.SubprocessError):
                    pass
        records[name] = info
    return {"format": 1, "tools": records,
            "validation": "executable version and local package source only; formatter/linter behavior requires separate real integration checks"}


def check_formatter_tools(home, records):
    if not isinstance(records, dict):
        raise RuntimeError("Invalid editor tool records.")
    expected = records.get("formatter_linter_tools", {})
    if (not isinstance(expected, dict) or expected.get("format") != 1
            or not isinstance(expected.get("tools"), dict) or set(expected["tools"]) != set(FORMATTER_LINTER_TOOLS)):
        raise RuntimeError("Formatter/linter records must contain all six configured tools.")
    for info in expected["tools"].values():
        if not isinstance(info, dict) or not isinstance(info.get("source"), dict) or not isinstance(info.get("rebuild"), dict):
            raise RuntimeError("Invalid formatter/linter source records.")
    env_path = str(home / ".local/share/nvim/mason/bin") + os.pathsep + os.environ.get("PATH", "")
    mason_root = home / ".local/share/nvim/mason"
    mason_records = {}
    if any(Path(found).resolve().is_relative_to(mason_root) for name in FORMATTER_LINTER_TOOLS
           if (found := shutil.which(name, path=env_path))):
        mason_records = mason_backend().capture_tools(home)
    current = formatter_linter_tools(home, env_path, mason_records)
    results = {}
    for name, original in expected["tools"].items():
        observed = current["tools"][name]
        reason = []
        if (original["rebuild"].get("method") not in ("existing-arch-package-transaction", "existing-mason-record")
                or original["source"].get("manager") not in ("pacman", "mason")):
            status, reason = "uncovered", ["recorded source has no supported reconstruction method"]
        else:
            if observed["validation"] != "version-only":
                reason.append("executable missing or version probe failed")
            if original.get("version") != observed["version"]:
                reason.append("executable version differs")
            if original.get("sha256") != observed["sha256"]:
                reason.append("executable content differs")
            if original["source"].get("manager") == "pacman":
                for key in ("manager", "package", "package_version", "repository", "official_repository"):
                    if original["source"].get(key) != observed["source"].get(key):
                        reason.append("package source or installed version differs")
                        break
                if original.get("realpath") != observed["realpath"]:
                    reason.append("canonical executable path differs")
            elif original["source"] != observed["source"]:
                reason.append("Mason source reference differs")
            status = "unverified" if reason else "verified"
        results[name] = {"status": status, "validation": "source-and-version-only", "observed": observed,
                         "reason": "; ".join(reason) if reason else "recorded executable, package source and version match"}
    status = "verified" if all(info["status"] == "verified" for info in results.values()) else "unverified"
    return {"status": status, "validation": "source-and-version-only", "tools": results,
            "functional_validation": "requires separate real formatter and linter integration checks"}


def external_tools(home):
    env_path = str(home / ".local/share/nvim/mason/bin") + os.pathsep + os.environ.get("PATH", "")
    result = {}
    for name in ("latex2text", "python3", "ipython3", "clangd", "pylsp", "stylua", "clang-format", "tree-sitter", "make", "cc", "topiary"):
        resolved = shutil.which(name, path=env_path)
        info = {"path": resolved, "version": None, "validation": "unavailable",
                "source": "legacy-mason" if resolved and "/mason/" in resolved else "PATH",
                "sha256": digest(Path(resolved)) if resolved else None}
        if resolved:
            try:
                output = run([resolved, "--version"], timeout=15, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
                info.update(version=output.splitlines()[0] if output else "unknown", validation="version-only")
            except (RuntimeError, subprocess.TimeoutExpired):
                info["validation"] = "version-unknown"
        result[name] = info
    topiary_config = home / ".config/topiary"
    topiary_cache = Path(os.environ.get("NVIM_EXTERNAL_CACHE_HOME") or os.environ.get("XDG_CACHE_HOME") or str(home / ".cache")) / "topiary"
    result["topiary"].update(configuration=files_digest(topiary_config) if topiary_config.is_dir() else None,
                             grammar_cache_path=str(topiary_cache),
                             grammar_cache=files_digest(topiary_cache) if topiary_cache.is_dir() else None)
    packages = {}
    for name in CORE_ARCH_PACKAGES:
        try:
            observed = run(["/usr/bin/pacman", "-Q", name], timeout=15).split(maxsplit=1)
            packages[name] = {"version": observed[1], "source": "Arch official package", "installed": True}
        except (OSError, RuntimeError, subprocess.SubprocessError, IndexError):
            packages[name] = {"version": None, "source": "Arch official package", "installed": False}
    code = ("import importlib.metadata,json; names=['pynvim','ipython','matplotlib','pygments','pylatexenc']; "
            "found={d.metadata['Name'].lower():d.version for d in importlib.metadata.distributions()}; "
            "print(json.dumps({n:found.get(n) for n in names}))")
    distributions = json.loads(run(["/usr/bin/python3", "-B", "-I", "-c", code], timeout=15))
    result["mason"] = mason_backend().capture_tools(home)
    result["formatter_linter_tools"] = formatter_linter_tools(home, env_path, result["mason"])
    result["jukit_core"] = {"source": "Arch system packages", "python": "/usr/bin/python3",
                            "ipython": "/usr/bin/ipython3", "required_packages": packages,
                            "distributions": distributions, "rebuild": "install recorded Arch package names before Neovim import",
                            "core_validation": "requires candidate startup and isolated cell/output/conversion checks",
                            "excluded": ["notebook browser", "HTML export", "PDF export", "terminal inline images"]}
    return result


def reusable_candidate(root, name):
    current = generation(root, name)
    options = [current]
    if (current / "attempts").is_dir():
        options.extend(sorted((current / "attempts").iterdir(), reverse=True))
    for candidate in options:
        regular_parents(candidate)
        manifest_path = candidate / "manifest.json"
        if not manifest_path.is_file():
            continue
        manifest = read_json(manifest_path)
        if not manifest.get("payload_sha256"):
            continue
        check_payload(candidate, manifest)
        if manifest.get("status") not in ("failed", "validated"):
            raise RuntimeError("Reusable payload is not an inactive completed attempt.")
        return candidate
    raise RuntimeError("No complete hash-verified candidate input is available; use a full --retry.")


def prepare(home, keep_versions, execute, generation_id=None, retry=False, reuse_candidate=False):
    root = root_for(home)
    source = source_state(home)
    previous = active_id(root)
    if reuse_candidate and (not retry or not generation_id or keep_versions):
        raise RuntimeError("--reuse-candidate requires --retry and --generation, and cannot combine with --keep-versions.")
    if reuse_candidate:
        keep_versions = True
    if retry and not generation_id:
        raise RuntimeError("Retry requires an explicit generation ID.")
    if generation_id and (not NAME.fullmatch(generation_id) or ((root / "generations" / generation_id).exists() and not retry)):
        raise RuntimeError("Candidate ID must be valid and not already exist; use --retry only for a failed candidate.")
    plan = {"status": "preview", "operation": "prepare", "active": previous,
            "source": source["path"], "target": str(root / "generations" / (generation_id or "<new-id>")),
            "keep_versions": keep_versions, "retry": retry, "reuse_candidate": reuse_candidate, "network": True, "build": True,
            "activate": False, "external_tools": "referenced, never installed"}
    if reuse_candidate:
        plan["reuse_input"] = str(reusable_candidate(root, generation_id))
    if not execute:
        return plan
    if not shutil.which("bwrap"):
        raise RuntimeError("Install bubblewrap before preparing an offline-validated candidate.")
    if not shutil.which("latex2text"):
        raise RuntimeError("Install Arch python-pylatexenc separately; latex2text is required.")
    with locked(root):
        if active_id(root) != previous or source_state(home) != source:
            raise RuntimeError("Configuration or active generation changed during preflight.")
        previous_attempts = set()
        if reuse_candidate:
            original = reusable_candidate(root, generation_id)
            original_manifest = read_json(original / "manifest.json")
            check_payload(original, original_manifest)
            if active_id(root) == generation_id:
                raise RuntimeError("An active generation cannot be reused in place.")
            target = generation(root, generation_id)
            if (target / "attempts").is_dir():
                previous_attempts = set((target / "attempts").iterdir())
        path = new_generation(root, generation_id, retry, reuse_candidate)
        reused = None
        if reuse_candidate:
            saved = set((path / "attempts").iterdir()) - previous_attempts
            if len(saved) != 1:
                raise RuntimeError("Cannot identify the preserved candidate input.")
            reused = saved.pop() if original == path else original
        manifest = {"format": 2, "generation": path.name, "architecture": platform.machine(),
                    "status": "preparing", "validated": False, "expected_active": previous,
                    "source_policy": "source", "source": source, "keep_versions": keep_versions,
                    "reuse_parser_artifacts": reuse_candidate, "reused_attempt": str(reused) if reused else None}
        write_json(path / "manifest.json", manifest)
        try:
            tree_copy(Path(source["path"]), path / "config/nvim")
            if files_digest(path / "config/nvim") != source["sha256"]:
                raise RuntimeError("Source changed while copying the candidate configuration.")
            data = path / "data/nvim"
            (data / "lazy").mkdir(parents=True)
            (data / "site").mkdir()
            old = reused or (generation(root, previous) if previous else None)
            if old:
                old_source_lock = read_json(old / "manifest.json").get("source", {}).get("sha256", {}).get("lazy-lock.json")
                if old_source_lock != source["sha256"].get("lazy-lock.json"):
                    raise RuntimeError("Source lockfile changed since the accepted generation; resolve the intended lock change before preparing an update.")
            if keep_versions and old:
                old_manifest = read_json(old / "manifest.json")
                previous_lock = old_manifest.get("source", {}).get("sha256", {}).get("lazy-lock.json")
                if previous_lock != source["sha256"].get("lazy-lock.json"):
                    raise RuntimeError("Source lockfile changed; --keep-versions cannot silently ignore it. Review the lock change or prepare a version update.")
                check_payload(old, old_manifest)
                tree_copy(old / "runtime", path / "runtime", preserve_links=True)
                manifest["runtime_source"] = old_manifest["runtime_source"]
                if reuse_candidate:
                    cleanup(data / "site")
                    tree_copy(old / "data/nvim/site", data / "site")
            else:
                tag = nvim_version("/usr/bin/nvim").removeprefix("NVIM ") if keep_versions else None
                manifest["runtime_source"] = acquire_runtime(path, tag)
            env = candidate_env(path, home)
            manifest["nvim_version"] = nvim_version(path / "runtime/bin/nvim", candidate=path, home=home)
            old_plugins = old / "data/nvim/lazy" if old else home / ".local/share/nvim/lazy"
            lock = read_json(path / "config/nvim/lazy-lock.json")
            if not keep_versions and old_plugins.is_dir():
                review = path / "plugin-edit-review"
                review.mkdir()
                edited = []
                for previous_plugin in sorted(old_plugins.iterdir()):
                    check_plugin_checkout(previous_plugin)
                    copied = review / previous_plugin.name
                    tree_copy(previous_plugin, copied, preserve_links=True)
                    if (copied / ".git").is_symlink():
                        raise RuntimeError(f"Plugin Git directory is a symlink: {previous_plugin.name}")
                    files_digest(copied, preserve_links=True)
                    changed = run(["git", "--git-dir", copied / ".git", "--work-tree", copied,
                                   "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null",
                                   "status", "--porcelain", "--untracked-files=all"],
                                  env={**os.environ, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"})
                    changes = changed.splitlines()
                    if previous_plugin.name == "nvim-treesitter":
                        generated = {}
                        remaining = []
                        for change in changes:
                            match = re.fullmatch(r"\?\? (parser/([a-z][a-z0-9_]*)\.so|parser-info/([a-z][a-z0-9_]*)\.revision)", change)
                            if match:
                                lang = match[2] or match[3]
                                revision = copied / "parser-info" / (lang + ".revision")
                                library = copied / "parser" / (lang + ".so")
                                if revision.is_file() and library.is_file() and re.fullmatch(r"[A-Za-z0-9_.-]+", revision.read_text(encoding="utf-8").strip()):
                                    generated[match[1]] = digest(copied / match[1])
                                    continue
                            remaining.append(change)
                        if generated:
                            manifest["legacy_generated_parser_artifacts"] = generated
                            write_json(path / "logs/legacy-generated-parsers.json", generated)
                        changes = remaining
                    if changes:
                        edited.append({"plugin": previous_plugin.name, "changes": changes})
                if edited:
                    write_json(path / "logs/local-plugin-edits.json", edited)
                    raise RuntimeError("Local plugin edits require an explicit decision; inspect logs/local-plugin-edits.json and use --keep-versions or reconcile the edits. Live plugins were not modified.")
                cleanup(review)
            lazy = data / "lazy/lazy.nvim"
            if keep_versions and (old_plugins / "lazy.nvim").is_dir():
                if not old and lock.get("lazy.nvim", {}).get("commit") != read_head(old_plugins / "lazy.nvim"):
                    raise RuntimeError("Legacy Lazy HEAD disagrees with the source lock; reconcile it explicitly.")
                tree_copy(old_plugins / "lazy.nvim", lazy, preserve_links=True)
            else:
                clone_plugin("https://github.com/folke/lazy.nvim.git", lazy, "refs/tags/stable")
            write_json(path / "manifest.json", manifest)
            specs = json.loads(helper_run(path, home, "specs"))
            if keep_versions and old:
                previous_specs = read_json(old / "manifest.json").get("selection_specs")
                if previous_specs != specs["plugins"]:
                    raise RuntimeError("Plugin version/source constraints changed or are unrecorded; use a reviewed version update instead of --keep-versions.")
            manifest["selection_specs"] = specs["plugins"]
            records = {}
            new_lock = {}
            for name, spec in sorted(specs["plugins"].items()):
                repo = data / "lazy" / name
                if name != "lazy.nvim":
                    if keep_versions and (old_plugins / name).is_dir():
                        if not old and lock.get(name, {}).get("commit") != read_head(old_plugins / name):
                            raise RuntimeError(f"Legacy plugin HEAD disagrees with the source lock: {name}. Reconcile the lock explicitly.")
                        tree_copy(old_plugins / name, repo, preserve_links=True)
                    else:
                        clone_plugin(spec["url"], repo)
                        ref = lock.get(name, {}).get("commit") if keep_versions else None
                        run(["git", "-C", repo, "checkout", "--detach", ref or choose_ref(repo, spec)])
                commit = read_head(repo)
                records[name] = {"url": github_url(spec["url"]), "commit": commit}
                new_lock[name] = {"commit": commit, "branch": spec.get("branch") or lock.get(name, {}).get("branch", "HEAD")}
            write_json(path / "config/nvim/lazy-lock.json", new_lock)
            manifest.update(plugins=records, parsers=specs["parsers"])
            write_json(path / "manifest.json", manifest)
            manifest["grammars"] = json.loads(helper_run(path, home, "inventory"))
            write_json(path / "manifest.json", manifest)
            (path / "logs/build.log").write_text(helper_run(path, home, "build"), encoding="utf-8")
            # Materialize parser query links inside this task-owned candidate.
            site = data / "site"
            copy = data / ".site-copy"
            tree_copy(site, copy)
            cleanup(site)
            copy.rename(site)
            (path / "logs/startup-initialize.log").write_text(
                helper_run(path, home, "startup", sandbox=True, initialize=True), encoding="utf-8")
            manifest["payload_sha256"] = payload_hashes(path)
            manifest["payload_executables"] = payload_executables(path)
            for name, info in records.items():
                info["content_sha256"] = files_digest(data / "lazy" / name, preserve_links=True)
            manifest["build_validation"] = "native commands completed; parser tasks awaited; real libraries and queries checked"
            manifest["native_artifacts"] = {
                name: value for name, value in manifest["payload_sha256"]["plugins"].items()
                if name.endswith((".so", ".dylib", ".dll"))}
            manifest["parser_artifacts"] = manifest["payload_sha256"]["site"]
            manifest["external_tools"] = external_tools(home)
            manifest["status"] = "prepared"
            write_json(path / "manifest.json", manifest)
            return validate(home, path.name, already_locked=True)
        except BaseException as error:
            manifest.update(status="failed", validated=False, failure=str(error))
            atomic_json(path / "manifest.json", manifest)
            print(f"[ERROR] Candidate retained: {path}", file=sys.stderr)
            raise


def validate(home, name, helper=HELPER, already_locked=False, check_source_state=True):
    root = root_for(home)
    if not already_locked:
        with locked(root):
            return validate(home, name, helper, already_locked=True, check_source_state=check_source_state)
    path = generation(root, name)
    manifest = read_json(path / "manifest.json")
    check_payload(path, manifest)
    if check_source_state and active_id(root) != name:
        check_source(home, manifest)
    if nvim_version(path / "runtime/bin/nvim", candidate=path, home=home) != manifest["nvim_version"]:
        raise RuntimeError("Runtime binary/version mismatch.")
    manifest.update(validated=False, status="validating")
    atomic_json(path / "manifest.json", manifest)
    try:
        report = helper_run(path, home, "verify", helper=helper, sandbox=True)
        startup_report = helper_run(path, home, "startup", helper=helper, sandbox=True)
        report += "\n" + startup_report
        evidence = next((json.loads(line.removeprefix("[VALIDATION] ")) for line in startup_report.splitlines()
                         if line.startswith("[VALIDATION] ")), None)
        if not evidence or not evidence.get("jukit_core_validation", {}).get("passed"):
            raise RuntimeError("Jukit core integration evidence is missing.")
        manifest["jukit_core_validation"] = evidence["jukit_core_validation"]
        manifest["lsp_validation"] = evidence["lsp_validation"]
        manifest["formatter_validation"] = evidence["formatter_validation"]
        manifest["interaction_validation"] = json.loads(helper_run(path, home, "interaction", sandbox=True))
        (path / "logs/verify.log").write_text(report, encoding="utf-8")
        check_payload(path, manifest)
        if check_source_state and active_id(root) != name:
            check_source(home, manifest)
        manifest["external_tools"] = external_tools(home)
        manifest["payload_executables"] = payload_executables(path)
        manifest.update(validated=True, status="validated", validation="offline-real-modules",
                        validated_at=datetime.now(timezone.utc).isoformat())
        atomic_json(path / "manifest.json", manifest)
        return {"status": "validated", "generation": name, "active": active_id(root) == name,
                "runtime": str(path / "runtime/bin/nvim"), "version": manifest["nvim_version"],
                "jukit_core_validation": manifest["jukit_core_validation"],
                "formatter_validation": manifest["formatter_validation"],
                "identity": content_identity(manifest)}
    except BaseException as error:
        manifest.update(status="failed", validated=False, failure=str(error))
        atomic_json(path / "manifest.json", manifest)
        raise


def launcher_text(root, *, legacy=False):
    revision = "2" if legacy else "3"
    bytecode = "" if legacy else "export PYTHONDONTWRITEBYTECODE=1\n"
    return """#!/usr/bin/env bash
set -euo pipefail
# managed-nvim-launcher-v""" + revision + """
root=""" + shlex.quote(str(root)) + """
selected=$(readlink -f -- "$root/active")
case "$selected" in
  "$root"/generations/*) ;;
  *) echo '[ERROR] Invalid managed Neovim generation.' >&2; exit 1 ;;
esac
if [ ! -x "$selected/runtime/bin/nvim" ]; then
  echo '[ERROR] Managed Neovim runtime is missing.' >&2
  exit 1
fi
unset NVIM_APPNAME VIMINIT EXINIT LUA_INIT LUA_PATH LUA_CPATH
""" + bytecode + """export NVIM_MANAGED_GENERATION="${selected##*/}"
export XDG_CONFIG_HOME="$selected/config"
export XDG_DATA_HOME="$selected/data"
export XDG_STATE_HOME="$selected/state"
export NVIM_EXTERNAL_CACHE_HOME="${NVIM_EXTERNAL_CACHE_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}}"
export XDG_CACHE_HOME="$selected/cache"
export VIMRUNTIME="$selected/runtime/share/nvim/runtime"
export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"
exec "$selected/runtime/bin/nvim" "$@"
"""


def path_state(path):
    if path.is_symlink():
        return {"link": os.readlink(path)}
    if path.is_file():
        return {"sha256": digest(path), "mode": path.stat().st_mode & 0o777}
    if path.exists():
        raise RuntimeError(f"Unexpected launcher type: {path}")
    return None


def launcher_version(home):
    wrapper = home / ".local/bin/nvim"
    if wrapper.is_symlink() or not wrapper.is_file() or not os.access(wrapper, os.X_OK):
        return None
    content = wrapper.read_bytes()
    for legacy, version in ((False, 3), (True, 2)):
        if content == launcher_text(root_for(home), legacy=legacy).encode("utf-8"):
            return version
    return None


def upgrade_launcher(home, execute, expected):
    root = root_for(home)
    wrapper = home / ".local/bin/nvim"
    regular_parents(wrapper.parent)
    current = active_id(root)
    version = launcher_version(home)
    if not current or version is None:
        raise RuntimeError("Expected an active generation and an exact managed launcher.")
    before = path_state(wrapper)
    new = launcher_text(root).encode("utf-8")
    result = {"status": "preview", "generation": current, "target": str(wrapper),
              "launcher_version": version, "before_sha256": before["sha256"],
              "after_sha256": hashlib.sha256(new).hexdigest()}
    if version == 3:
        return {**result, "status": "unchanged"}
    safety = root / "safety" / ("launcher-v2-" + before["sha256"] + ".sh")
    stage = wrapper.with_name(".nvim-launcher-upgrade.tmp")
    result.update(safety_backup=str(safety), temporary=str(stage))
    if not execute:
        return result
    if expected != before["sha256"]:
        raise RuntimeError("Launcher SHA-256 differs from the reviewed preview.")
    with locked(root):
        if active_id(root) != current or launcher_version(home) != 2 or path_state(wrapper) != before:
            raise RuntimeError("Active generation or launcher changed before upgrade.")
        regular_parents(safety.parent)
        safety.parent.mkdir(exist_ok=True)
        if not safety.exists() and not safety.is_symlink():
            with safety.open("xb") as stream:
                try:
                    stream.write(launcher_text(root, legacy=True).encode("utf-8"))
                    stream.flush()
                    os.fchmod(stream.fileno(), before["mode"])
                    os.fsync(stream.fileno())
                except BaseException:
                    if os.path.samestat(os.fstat(stream.fileno()), safety.lstat()):
                        cleanup(safety)
                    raise
        if path_state(safety) != before:
            raise RuntimeError(f"Launcher safety copy differs: {safety}")
        with stage.open("xb") as stream:
            try:
                stream.write(new)
                stream.flush()
                os.fchmod(stream.fileno(), before["mode"])
                os.fsync(stream.fileno())
                if active_id(root) != current or path_state(wrapper) != before:
                    raise RuntimeError("Active generation or launcher changed before replacement.")
                if (not os.path.samestat(os.fstat(stream.fileno()), stage.lstat())
                        or digest(stage) != result["after_sha256"]):
                    raise RuntimeError("Staged launcher changed before replacement.")
                os.replace(stage, wrapper)
            finally:
                if stage.exists() and os.path.samestat(os.fstat(stream.fileno()), stage.lstat()):
                    cleanup(stage)
    return {**result, "status": "upgraded", "launcher_version": 3}


def activate(home, name, execute, rollback=False, expect_identity=None):
    root = root_for(home)
    path = generation(root, name)
    manifest = read_json(path / "manifest.json")
    current = active_id(root)
    check_payload(path, manifest)
    if not manifest.get("validated") or manifest.get("status") != "validated":
        raise RuntimeError("Candidate has not passed validation.")
    if not rollback:
        check_source(home, manifest)
        if current != manifest.get("expected_active") and current != name:
            raise RuntimeError("Active generation changed since preparation; prepare or import again.")
    review_manifest = dict(manifest)
    review_manifest["external_tools"] = external_tools(home)
    result = {"status": "preview", "operation": "rollback" if rollback else "activate",
              "generation": name, "previous": current, "runtime": str(path / "runtime/bin/nvim"),
              "external_tools_rollback": False, "identity": content_identity(review_manifest),
              "tools_changed_since_validation": review_manifest["external_tools"] != manifest.get("external_tools"),
              "writes": [str(root / "active"), str(home / ".local/bin/nvim")],
              "launcher_state": path_state(home / ".local/bin/nvim")}
    if not execute:
        return result
    if not expect_identity or not re.fullmatch(r"[0-9a-f]{64}", expect_identity):
        raise RuntimeError("Activation requires --expect-identity from the reviewed preview or validation result.")
    if expect_identity != result["identity"]:
        raise RuntimeError("Candidate identity changed; review a fresh preview before activation.")
    with locked(root):
        if active_id(root) != current:
            raise RuntimeError("Active generation changed during preflight.")
        check_payload(path, manifest)
        if not rollback:
            check_source(home, manifest)
        validate(home, name, already_locked=True, check_source_state=not rollback)
        manifest = read_json(path / "manifest.json")
        if content_identity(manifest) != expect_identity:
            raise RuntimeError("Current tools or candidate identity changed during fresh validation; review again before activation.")
        wrapper = home / ".local/bin/nvim"
        regular_parents(wrapper.parent)
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        previous_launcher = path_state(wrapper)
        text = launcher_text(root)
        owned = launcher_version(home) == 3
        if current == name and owned:
            return {"status": "unchanged", "generation": name, "active": True, "validation": "fresh", "identity": expect_identity}
        safety = root / "safety" / (datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8])
        required = 64 * 1024 ** 2
        if current is None:
            for old in (home / ".config/nvim", home / ".local/share/nvim/lazy", home / ".local/share/nvim/site"):
                if old.is_dir():
                    required += sum((Path(parent) / file).stat().st_size
                                    for parent, _, files in os.walk(old, followlinks=True) for file in files)
        if shutil.disk_usage(root).free < required:
            raise RuntimeError("Insufficient free space to preserve the legacy editor.")
        safety.mkdir(parents=True)
        if previous_launcher is not None:
            if wrapper.is_symlink():
                (safety / "launcher").symlink_to(os.readlink(wrapper))
            else:
                shutil.copy2(wrapper, safety / "launcher")
        if current is None:
            for source, label in ((home / ".config/nvim", "config"), (home / ".local/share/nvim/lazy", "plugins"),
                                  (home / ".local/share/nvim/site", "site")):
                if source.is_dir():
                    tree_copy(source, safety / label)
        atomic_json(safety / "transition.json", {"previous": current, "next": name, "launcher": previous_launcher})
        temp = root / (".active-" + uuid.uuid4().hex)
        wrapper_temp = wrapper.with_name(".nvim-" + uuid.uuid4().hex)
        try:
            if path_state(wrapper) != previous_launcher or active_id(root) != current:
                raise RuntimeError("Launcher or active state changed while preserving the old environment.")
            check_payload(path, manifest)
            if not rollback:
                check_source(home, manifest)
            temp.symlink_to("generations/" + name)
            if not owned:
                wrapper_temp.write_text(text, encoding="utf-8")
                wrapper_temp.chmod(0o755)
            try:
                os.replace(temp, root / "active")
                if not owned:
                    os.replace(wrapper_temp, wrapper)
            except BaseException:
                # Reconcile actual state: interruption may follow a successful rename.
                if not owned and path_state(wrapper) != previous_launcher:
                    if wrapper.is_file() and not wrapper.is_symlink() and wrapper.read_text(encoding="utf-8", errors="replace") == text:
                        if previous_launcher is None:
                            cleanup(wrapper)
                        else:
                            if wrapper_temp.exists() or wrapper_temp.is_symlink():
                                cleanup(wrapper_temp)
                            if "link" in previous_launcher:
                                wrapper_temp.symlink_to(previous_launcher["link"])
                            else:
                                shutil.copy2(safety / "launcher", wrapper_temp)
                            os.replace(wrapper_temp, wrapper)
                    else:
                        raise RuntimeError(f"Launcher changed unexpectedly; preserve recovery evidence at {safety}")
                if active_id(root) == name:
                    if current is None:
                        cleanup(root / "active")
                    else:
                        if temp.exists() or temp.is_symlink():
                            cleanup(temp)
                        temp.symlink_to("generations/" + current)
                        os.replace(temp, root / "active")
                raise
        finally:
            for item in (temp, wrapper_temp):
                if item.exists() or item.is_symlink():
                    cleanup(item)
        result.update(status="active", active=True, safety_backup=str(safety))
        return result


def status(home):
    root = root_for(home)
    current = active_id(root)
    result = {"available": current is not None, "active": current, "generation": current,
              "version": None, "architecture": platform.machine(), "validated": False, "runtime": None,
              "launcher_consistent": False,
              "generations": []}
    parent = root / "generations"
    if parent.is_dir():
        for path in sorted(parent.iterdir()):
            if path.is_dir() and not path.is_symlink() and (path / "manifest.json").is_file():
                item = read_json(path / "manifest.json")
                result["generations"].append({"generation": path.name, "status": item.get("status"),
                                               "validated": item.get("validated", False)})
    if current:
        path = generation(root, current)
        manifest = read_json(path / "manifest.json")
        result.update(version=manifest.get("nvim_version"), validated=manifest.get("validated", False),
                      runtime=str(path / "runtime/bin/nvim"))
        try:
            check_payload(path, manifest)
        except RuntimeError as error:
            result.update(validated=False, integrity_error=str(error))
        version = launcher_version(home)
        result.update(launcher_consistent=version is not None, launcher_version=version,
                      launcher_upgrade_required=version == 2)
        if not result["launcher_consistent"]:
            result.update(available=False, validated=False,
                          launcher_error="Active pointer and managed launcher are inconsistent; review and rerun activation for the same generation.")
    return result


def validate_manifest(stage):
    manifest = read_json(stage / "manifest.json")
    if manifest.get("format") == 1:
        if files_digest(stage / "config") != manifest["config_sha256"]:
            raise RuntimeError("Legacy configuration checksum mismatch.")
        if digest(stage / "runtime.tar.gz") != manifest["runtime_sha256"]:
            raise RuntimeError("Legacy runtime checksum mismatch.")
        if manifest["architecture"] != platform.machine():
            raise RuntimeError("Legacy snapshot architecture differs from this host.")
        if not re.fullmatch(r"NVIM v\d+\.\d+\.\d+", manifest.get("nvim_version", "")):
            raise RuntimeError("Invalid legacy runtime version.")
        if not manifest.get("parsers") or any(not re.fullmatch(r"[a-z][a-z0-9_]*", lang) for lang in manifest["parsers"]):
            raise RuntimeError("Invalid legacy parser inventory.")
        lock = read_json(stage / "config/lazy-lock.json")
        if not {"lazy.nvim", "nvim-treesitter"}.issubset(lock):
            raise RuntimeError("Legacy snapshot lacks Lazy or Treesitter.")
        if not lock or set(lock) != set(manifest["plugins"]):
            raise RuntimeError("Legacy plugin lock and manifest disagree.")
        for name, info in manifest["plugins"].items():
            if not NAME.fullmatch(name) or not COMMIT.fullmatch(info["commit"]) or info["commit"] != lock[name]["commit"]:
                raise RuntimeError("Invalid legacy plugin entry.")
            github_url(info["url"])
        temporary = Path(tempfile.mkdtemp(prefix=".legacy-runtime-check-", dir=stage))
        try:
            safe_extract(stage / "runtime.tar.gz", temporary)
        finally:
            cleanup(temporary)
        raise NeedsRebuild("needs-rebuild: legacy format 1 has no complete plugin/native payload; rebuild separately with explicit network authorization.")
    if manifest.get("format") != 2:
        raise RuntimeError("Unsupported Neovim snapshot format.")
    if manifest.get("architecture") != platform.machine():
        raise RuntimeError("Snapshot architecture differs from this host.")
    if not manifest.get("validated"):
        raise RuntimeError("Snapshot is not an accepted generation.")
    expected = manifest.get("payload_sha256", {})
    for name in ("config", "plugins", "site"):
        if files_digest(stage / name, preserve_links=name == "plugins") != expected.get(name):
            raise RuntimeError(f"Snapshot {name} checksum mismatch.")
    if digest(stage / "runtime.tar.gz") != manifest.get("runtime_archive_sha256"):
        raise RuntimeError("Snapshot runtime archive checksum mismatch.")
    for name, info in manifest.get("plugins", {}).items():
        if not NAME.fullmatch(name) or read_head(stage / "plugins" / name) != info["commit"]:
            raise RuntimeError("Snapshot plugin HEAD mismatch.")
    return manifest


def backup(home, archive):
    root = root_for(home)
    regular_parents(archive.parent)
    if archive.exists() or archive.is_symlink():
        raise RuntimeError("Snapshot target exists; choose a new archive path.")
    with locked(root):
        current = active_id(root)
        if not current:
            raise RuntimeError("No managed active generation; prepare, validate and activate one first.")
        path = generation(root, current)
        manifest = read_json(path / "manifest.json")
        check_payload(path, manifest)
        if not manifest.get("validated") or manifest.get("status") != "validated":
            raise RuntimeError("Active generation is not validated.")
        validate(home, current, already_locked=True)
        manifest = read_json(path / "manifest.json")
        archive.parent.mkdir(parents=True, exist_ok=True)
        temp = Path(tempfile.mkdtemp(prefix=".nvim-backup-", dir=archive.parent))
        try:
            for source, name in ((path / "config/nvim", "config"), (path / "data/nvim/lazy", "plugins"),
                                 (path / "data/nvim/site", "site")):
                tree_copy(source, temp / name, preserve_links=name == "plugins")
            with tarfile.open(temp / "runtime.tar.gz", "w:gz", dereference=False) as stream:
                stream.add(path / "runtime", arcname="runtime")
            manifest["runtime_archive_sha256"] = digest(temp / "runtime.tar.gz")
            manifest["external_tools"] = external_tools(home)
            write_json(temp / "manifest.json", manifest)
            validate_manifest(temp)
            check_payload(path, manifest)
            with tarfile.open(temp / "snapshot.tar.gz", "w:gz", dereference=False) as stream:
                for name in ("manifest.json", "config", "runtime.tar.gz", "plugins", "site"):
                    stream.add(temp / name, arcname=name)
            # Exclusive publication; preserve existing archives on races.
            os.link(temp / "snapshot.tar.gz", archive)
        finally:
            cleanup(temp)
        return {"status": "complete", "generation": current, "format": 2, "archive": str(archive)}


def stage(archive, target):
    safe_extract(archive, target)
    manifest = validate_manifest(target)
    unpack = target / ".runtime-unpack"
    safe_extract(target / "runtime.tar.gz", unpack)
    if not (unpack / "runtime/bin/nvim").is_file() or len(list(unpack.iterdir())) != 1:
        raise RuntimeError("Snapshot runtime layout is invalid.")
    if files_digest(unpack / "runtime", preserve_links=True) != manifest["payload_sha256"]["runtime"]:
        raise RuntimeError("Snapshot runtime content mismatch.")
    (unpack / "runtime").rename(target / "runtime")
    cleanup(unpack)
    if not os.access(target / "runtime/bin/nvim", os.X_OK):
        raise RuntimeError("Staged runtime is not executable.")
    if "payload_executables" in manifest and payload_executables(target, staged=True) != manifest["payload_executables"]:
        raise RuntimeError("Snapshot executable permissions differ from its manifest.")
    return {"status": "ready", "format": 2, "generation": manifest["generation"], "target": str(target)}


def validated_stage_identity(source):
    source = Path(source)
    regular_parents(source)
    for name in ("config", "runtime", "plugins", "site"):
        regular_parents(source / name)
    manifest = validate_manifest(source)
    if files_digest(source / "runtime", preserve_links=True) != manifest["payload_sha256"]["runtime"]:
        raise RuntimeError("Staged runtime differs from its manifest.")
    binary = source / "runtime/bin/nvim"
    if not binary.is_file() or not os.access(binary, os.X_OK) or not binary.resolve().is_relative_to((source / "runtime").resolve()):
        raise RuntimeError("Staged runtime executable is unavailable or outside its bundle.")
    if "payload_executables" in manifest and payload_executables(source, staged=True) != manifest["payload_executables"]:
        raise RuntimeError("Staged executable permissions differ from the manifest.")
    return {"identity": content_identity(manifest), "manifest_sha256": digest(source / "manifest.json"),
            "path": str(source.resolve())}


def equivalent(home, source):
    validated_stage_identity(source)
    incoming = read_json(source / "manifest.json")
    root = root_for(home)
    current = active_id(root)
    if not current:
        return {"equivalent": False, "generation": None, "validated": False, "reason": "no-active-generation"}
    path = generation(root, current)
    manifest = read_json(path / "manifest.json")
    try:
        check_payload(path, manifest)
    except RuntimeError as error:
        return {"equivalent": False, "generation": current, "validated": False, "reason": str(error)}
    if launcher_version(home) is None:
        return {"equivalent": False, "generation": current, "validated": False, "reason": "launcher-mismatch"}
    same = same_import_payload(path, manifest, source, incoming)
    validated = manifest.get("validated", False) and manifest.get("status") == "validated"
    if active_id(root) != current:
        return {"equivalent": False, "generation": current, "validated": False, "reason": "active-changed-during-check"}
    return {"equivalent": same and validated, "generation": current, "validated": validated,
            "reason": "identical-verified-payload" if same and validated else "different-or-unvalidated-payload"}


def same_import_payload(path, manifest, source, incoming):
    fields = ("format", "architecture", "nvim_version", "runtime_source", "payload_sha256",
              "selection_specs", "plugins", "parsers", "grammars")
    return (all(manifest.get(key) == incoming.get(key) for key in fields)
            and payload_executables(path) == payload_executables(source, staged=True))


def restore(home, source, helper, execute):
    staged_identity = validated_stage_identity(source)
    manifest = read_json(source / "manifest.json")
    if not execute:
        return {"status": "preview", "operation": "restore", "source": str(source),
                "target": str(root_for(home) / "generations/<new-id>"), "activate": False, "network": False}
    root = root_for(home)
    with locked(root):
        if validated_stage_identity(source) != staged_identity:
            raise RuntimeError("Staged snapshot changed during restore preflight.")
        current = active_id(root)
        parent = root / "generations"
        candidates = sorted(parent.iterdir()) if parent.is_dir() else []
        if current:
            candidates = [generation(root, current)] + [path for path in candidates if path.name != current]
        for existing in candidates:
            if existing.is_symlink() or not existing.is_dir() or not (existing / "manifest.json").is_file():
                continue
            previous = read_json(existing / "manifest.json")
            if existing.name != current and previous.get("source_policy") != "imported":
                continue
            if not same_import_payload(existing, previous, source, manifest):
                continue
            check_payload(existing, previous)
            if existing.name != current and previous.get("expected_active") != current:
                raise RuntimeError("Matching imported candidate has a stale active predecessor; review it before reuse.")
            result = validate(home, existing.name, helper=helper, already_locked=True)
            result.update(reused=True, reason="identical-payload-freshly-validated")
            return result
        path = new_generation(root)
        try:
            for old, new in (("config", "config/nvim"), ("plugins", "data/nvim/lazy"),
                             ("site", "data/nvim/site"), ("runtime", "runtime")):
                tree_copy(source / old, path / new, preserve_links=old in ("plugins", "runtime"))
            manifest.update(generation=path.name, imported_generation=manifest["generation"], status="prepared",
                            validated=False, expected_active=active_id(root), source_policy="imported",
                            local_source_at_import=optional_source(home))
            write_json(path / "manifest.json", manifest)
            return validate(home, path.name, helper=helper, already_locked=True)
        except BaseException as error:
            manifest.update(status="failed", validated=False, failure=str(error))
            atomic_json(path / "manifest.json", manifest)
            print(f"[ERROR] Candidate retained: {path}", file=sys.stderr)
            raise


def main():
    parser = argparse.ArgumentParser(description="Prepare, validate and atomically select managed Neovim generations.")
    parser.add_argument("--home", type=Path, default=Path.home())
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "tools", "formatter-check", "prepare", "validate", "activate", "rollback", "launcher-upgrade", "backup", "stage", "restore", "equivalent", "mason-restore"):
        cmd = commands.add_parser(name)
        cmd.add_argument("--json", action="store_true")
        if name in ("prepare", "activate", "rollback", "launcher-upgrade", "restore", "mason-restore"):
            cmd.add_argument("--run", action="store_true", help="Perform this operation; otherwise preview only.")
        if name == "launcher-upgrade":
            cmd.add_argument("--expect-sha256", help="Require the exact v2 launcher hash shown by the preview.")
        if name == "prepare":
            cmd.add_argument("--keep-versions", action="store_true")
            cmd.add_argument("--generation", help="Use this candidate ID for an exact reviewed target.")
            cmd.add_argument("--retry", action="store_true", help="Preserve the inactive prior attempt, then prepare again.")
            cmd.add_argument("--reuse-candidate", action="store_true", help="With --retry, reuse only hash-verified runtime/plugins/parsers; keep version constraints unchanged.")
        if name in ("validate", "activate", "rollback"):
            cmd.add_argument("generation")
        if name in ("activate", "rollback", "mason-restore"):
            cmd.add_argument("--expect-identity", help="Require this reviewed stable content/tool or reconstruction-plan identity for --run.")
        if name in ("backup", "stage"):
            cmd.add_argument("archive", type=Path)
        if name == "stage":
            cmd.add_argument("target", type=Path)
        if name in ("mason-restore", "formatter-check"):
            cmd.add_argument("tools_json", type=Path)
        if name in ("restore", "equivalent", "mason-restore"):
            cmd.add_argument("source", type=Path)
        if name in ("restore", "mason-restore"):
            cmd.add_argument("lua_helper", type=Path)
    args = parser.parse_args()
    if args.command in ("activate", "rollback", "mason-restore") and args.run and not args.expect_identity:
        parser.error("--run requires --expect-identity from the reviewed preview or validation result")
    def interrupted(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupted)
    home = args.home.expanduser().absolute()
    try:
        regular_parents(home)
        if args.command == "status":
            result = status(home)
        elif args.command == "launcher-upgrade":
            result = upgrade_launcher(home, args.run, args.expect_sha256)
        elif args.command == "tools":
            result = external_tools(home)
        elif args.command == "formatter-check":
            result = check_formatter_tools(home, read_json(args.tools_json))
        elif args.command == "prepare":
            result = prepare(home, args.keep_versions, args.run, args.generation, args.retry, args.reuse_candidate)
        elif args.command == "validate":
            result = validate(home, args.generation)
        elif args.command in ("activate", "rollback"):
            result = activate(home, args.generation, args.run, rollback=args.command == "rollback", expect_identity=args.expect_identity)
        elif args.command == "backup":
            result = backup(home, args.archive.absolute())
        elif args.command == "stage":
            result = stage(args.archive.absolute(), args.target.absolute())
        elif args.command == "equivalent":
            result = equivalent(home, args.source.absolute())
        elif args.command == "mason-restore":
            validated_stage_identity(args.source.absolute())
            result = mason_backend().restore_tools(home, read_json(args.tools_json)["mason"],
                args.source.absolute(), args.lua_helper.absolute(), execute=args.run, expect_identity=args.expect_identity)
        else:
            result = restore(home, args.source.absolute(), args.lua_helper.absolute(), args.run)
        if args.json:
            print(json.dumps(result, sort_keys=True))
        else:
            for key, value in result.items():
                print(f"{key}: {value}")
        return 0
    except NeedsRebuild as error:
        if args.json:
            print(json.dumps({"status": "needs-rebuild", "format": 1, "reason": str(error)}))
        print(f"[ERROR] {error}", file=sys.stderr)
        return 3
    except (OSError, RuntimeError, ValueError, KeyError, TypeError, tarfile.TarError, subprocess.SubprocessError) as error:
        print(f"[ERROR] {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("[ERROR] Interrupted; incomplete candidates remain available for diagnosis.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
