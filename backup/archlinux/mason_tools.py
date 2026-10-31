"""Internal Mason records and reconstruction for nvim_state.py."""

from contextlib import contextmanager
from datetime import datetime, timezone
import ctypes
import email
import fcntl
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import signal
import shutil
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request
import uuid
import zipfile


ROOT = ".local/share/nvim/mason"
PROVENANCE = "mason-rebuild.json"
SOURCES = {
    "clangd": ("pkg:github/clangd/clangd@", "clangd"),
    "python-lsp-server": ("pkg:pypi/python-lsp-server@", "pylsp"),
    "clang-format": ("pkg:pypi/clang-format@", "clang-format"),
    "stylua": ("pkg:github/johnnymorganz/stylua@", "stylua"),
}
BIN_NAMES = {
    "clangd": {"clangd"}, "python-lsp-server": {"pylsp"},
    "clang-format": {"clang-format", "git-clang-format", "clang-format-diff.py"},
    "stylua": {"stylua"},
}
SHA = re.compile(r"[0-9a-f]{64}")
VERSION = re.compile(r"v?\d[0-9A-Za-z.+-]*")


def _json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path, value):
    parent_fd = _directory_fd(path.parent)
    try:
        descriptor = os.open(path.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=parent_fd)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
    finally:
        os.close(parent_fd)


def _hash(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _object_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _exists(path):
    return path.exists() or path.is_symlink()


def _parents(path):
    for part in (path, *path.parents):
        if part.is_symlink() or (part.exists() and not part.is_dir()):
            raise RuntimeError(f"Mason path is not a regular directory: {part}")


def _home(home):
    home = Path(home)
    if not home.is_absolute() or ".." in home.parts or home == Path("/"):
        raise RuntimeError("Mason target requires an absolute home directory.")
    _parents(home / ROOT)
    return home


def _relative(value):
    if not isinstance(value, str):
        raise RuntimeError("Invalid Mason relative path.")
    path = PurePosixPath(value)
    if path.is_absolute() or not path.parts or ".." in path.parts or str(path) != value:
        raise RuntimeError(f"Unsafe Mason relative path: {value}")
    return value


def _identity(value):
    return [value.st_dev, value.st_ino]


def _directory_fd(path, create=False):
    path = Path(path)
    if not path.is_absolute() or ".." in path.parts:
        raise RuntimeError(f"Unsafe Mason directory: {path}")
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            if create:
                try:
                    os.mkdir(part, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = next_fd
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def _directory_identity(path, create=False):
    descriptor = _directory_fd(path, create=create)
    try:
        return _identity(os.fstat(descriptor))
    finally:
        os.close(descriptor)


def _path_identity(path):
    try:
        return _identity(path.lstat())
    except FileNotFoundError:
        return None


def _temporary(prefix, parent=None):
    path = Path(tempfile.mkdtemp(prefix=prefix, dir=parent))
    descriptor = _directory_fd(path)
    return path, {"fd": descriptor, "identity": _identity(os.fstat(descriptor)),
                  "parent": _directory_identity(path.parent)}


def _cleanup(path, owned):
    parent_fd = _directory_fd(path.parent)
    try:
        if (_identity(os.fstat(parent_fd)) != owned["parent"] or
                _identity(os.fstat(owned["fd"])) != owned["identity"] or
                _path_identity(path) != owned["identity"]):
            raise RuntimeError(f"Temporary directory moved or replaced; retained: {path}")
        quarantine = path.with_name(".mason-cleanup-" + uuid.uuid4().hex)
        _rename(path, quarantine, owned["identity"], owned["parent"], owned["parent"])
        if _path_identity(quarantine) != owned["identity"]:
            if not _exists(path):
                _rename(quarantine, path, _path_identity(quarantine), owned["parent"], owned["parent"])
            raise RuntimeError(f"Temporary cleanup identity changed; retained: {path}, {quarantine}")
        os.environ["CODEX_TEMP_CLEANUP"] = "1"
        # Delete through the creation-time fd, never through a replacement path.
        for name in os.listdir(owned["fd"]):
            mode = os.stat(name, dir_fd=owned["fd"], follow_symlinks=False).st_mode
            if stat.S_ISDIR(mode):
                shutil.rmtree(name, dir_fd=owned["fd"])
            else:
                os.unlink(name, dir_fd=owned["fd"])
        if _path_identity(quarantine) != owned["identity"]:
            raise RuntimeError(f"Temporary directory moved during cleanup; retained: {quarantine}")
        os.rmdir(quarantine.name, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)


@contextmanager
def _termination_guard():
    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"Mason operation interrupted by signal {signum}.")
    previous = {signum: signal.signal(signum, interrupted) for signum in (signal.SIGTERM, signal.SIGHUP)}
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def _tree_hash(root, payload=False):
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError(f"Missing regular Mason package: {root}")
    items = []
    def unreadable(error):
        raise error
    for parent, dirs, files in os.walk(root, followlinks=False, onerror=unreadable):
        parent = Path(parent)
        if payload:
            dirs[:] = [name for name in dirs if name != "__pycache__"]
        for name in sorted(dirs + files):
            path = parent / name
            relative = path.relative_to(root).as_posix()
            if payload and (relative in (PROVENANCE, "mason-receipt.json") or name.endswith((".pyc", ".pyo"))):
                continue
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                value = [relative, "link", os.readlink(path)]
            elif stat.S_ISREG(mode):
                value = [relative, "file", stat.S_IMODE(mode), _hash(path)]
            elif stat.S_ISDIR(mode):
                value = [relative, "dir", stat.S_IMODE(mode)]
            else:
                raise RuntimeError(f"Unsupported Mason file: {path}")
            items.append(value)
    return _object_hash(sorted(items))


def _fingerprint(path):
    if path.is_symlink():
        return {"link": os.readlink(path)}
    if path.is_dir():
        return {"tree": _tree_hash(path)}
    if path.is_file():
        return {"file": _hash(path), "mode": stat.S_IMODE(path.stat().st_mode)}
    if _exists(path):
        raise RuntimeError(f"Unsupported Mason target: {path}")
    return None


def _registry(value):
    if not isinstance(value, dict) or any(value.get(k) != v for k, v in
            (("proto", "github"), ("namespace", "mason-org"), ("name", "mason-registry"))):
        raise RuntimeError("Mason requires the recorded official GitHub registry.")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}-[a-z0-9-]+", str(value.get("version", ""))):
        raise RuntimeError("Mason registry has no fixed release tag.")
    checksums = value.get("checksums", {})
    if not isinstance(checksums, dict) or any(not SHA.fullmatch(str(checksums.get(name, ""))) for name in ("registry.json", "registry.json.zip")):
        raise RuntimeError("Mason registry requires both original SHA256 checksums.")
    return {key: value[key] for key in ("proto", "namespace", "name", "version", "checksums")}


def _version(name, source):
    prefix = SOURCES[name][0]
    suffix = "?extra=all" if name == "python-lsp-server" else ""
    if not isinstance(source, str) or not source.startswith(prefix) or (suffix and not source.endswith(suffix)):
        raise RuntimeError(f"Unknown Mason source for {name}.")
    version = source[len(prefix):]
    if suffix:
        version = version[:-len(suffix)]
    if not VERSION.fullmatch(version):
        raise RuntimeError(f"Missing or unsafe Mason version for {name}.")
    return version


def _links(name, value):
    if (not isinstance(value, dict) or set(value) - {"bin", "share", "opt"} or
            any(not isinstance(value.get(kind, {}), dict) for kind in ("bin", "share", "opt"))):
        raise RuntimeError(f"Invalid Mason links for {name}.")
    expected_share = {f"mason-schemas/lsp/{name}.json"} if name in ("clangd", "python-lsp-server") else set()
    if set(value.get("bin", {})) != BIN_NAMES[name] or set(value.get("share", {})) - expected_share or value.get("opt"):
        raise RuntimeError(f"Unexpected Mason link names for {name}.")
    result = {}
    for kind in ("bin", "share", "opt"):
        result[kind] = {_relative(link): _relative(target) for link, target in value.get(kind, {}).items()}
    return result


def _distributions(package):
    result = {}
    _parents(package / "venv/lib")
    for info in sorted((package / "venv/lib").glob("python*/site-packages/*.dist-info")):
        _parents(info.parent)
        if info.is_symlink() or (info / "METADATA").is_symlink() or (info / "direct_url.json").exists():
            raise RuntimeError(f"Unverified Python distribution source: {info}")
        meta = email.message_from_string((info / "METADATA").read_text(encoding="utf-8"))
        name = re.sub(r"[-_.]+", "-", meta.get("Name", "")).lower()
        version = meta.get("Version", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name) or not VERSION.fullmatch(version) or name in result:
            raise RuntimeError(f"Invalid Python distribution metadata: {info}")
        result[name] = version
    return result


def _read_tool(root, name):
    package = root / "packages" / name
    _parents(package)
    receipt_path = package / "mason-receipt.json"
    if receipt_path.is_symlink() or not receipt_path.is_file():
        raise RuntimeError(f"Mason receipt is missing: {receipt_path}")
    receipt = _json(receipt_path)
    if (not isinstance(receipt, dict) or not isinstance(receipt.get("source"), dict) or
            receipt.get("schema_version") != "2.0" or receipt.get("name") != name or receipt["source"].get("type") != "registry+v1"):
        raise RuntimeError(f"Unsupported Mason receipt for {name}.")
    source = receipt["source"]["id"]
    version = _version(name, source)
    registry = receipt.get("registry", {})
    if not isinstance(registry, dict) or not isinstance(receipt["source"].get("raw"), dict):
        raise RuntimeError(f"Incomplete Mason source receipt for {name}.")
    if registry.get("proto") == "file":
        provenance_path = package / PROVENANCE
        if provenance_path.is_symlink():
            raise RuntimeError(f"Linked Mason reconstruction record: {provenance_path}")
        provenance = _json(provenance_path)
        if not isinstance(provenance, dict) or provenance.get("receipt_sha256") != _hash(receipt_path) or provenance.get("source") != source:
            raise RuntimeError(f"Mason reconstruction provenance does not bind {name}.")
        registry = provenance.get("registry")
    record = {"source": source, "version": version, "registry": _registry(registry),
              "raw_source_sha256": _object_hash(receipt["source"]["raw"]),
              "links": _links(name, receipt["links"]), "receipt_sha256": _hash(receipt_path),
              "content_sha256": _tree_hash(package, payload=True),
              "python_distributions": _distributions(package)}
    for kind, links in record["links"].items():
        for link, target in links.items():
            actual = root / kind / link
            _parents(actual.parent)
            expected = package / target
            if not actual.is_symlink() or actual.resolve() != expected.resolve() or not expected.is_file():
                raise RuntimeError(f"Mason link is missing or changed: {actual}")
            if not expected.resolve().is_relative_to(package):
                raise RuntimeError(f"Mason executable escapes its package: {expected}")
    return record


def validate_records(records):
    if not isinstance(records, dict) or records.get("format") != 1 or records.get("root") != ROOT:
        raise RuntimeError("Missing supported Mason reconstruction records.")
    if (records.get("architecture") != platform.machine() or not isinstance(records.get("tools"), dict) or
            set(records["tools"]) != set(SOURCES)):
        raise RuntimeError("Mason records require this architecture and all four original tools.")
    for name, record in records["tools"].items():
        if not isinstance(record, dict):
            raise RuntimeError(f"Invalid Mason record for {name}.")
        if _version(name, record.get("source")) != record.get("version"):
            raise RuntimeError(f"Mason version and source disagree for {name}.")
        _registry(record.get("registry"))
        _links(name, record.get("links"))
        if any(not SHA.fullmatch(str(record.get(key, ""))) for key in
               ("raw_source_sha256", "receipt_sha256", "content_sha256")):
            raise RuntimeError(f"Incomplete Mason checksums for {name}.")
        distributions = record.get("python_distributions")
        if not isinstance(distributions, dict) or any(not re.fullmatch(r"[a-z0-9][a-z0-9-]*", key) or
                not isinstance(value, str) or not VERSION.fullmatch(value) for key, value in distributions.items()):
            raise RuntimeError(f"Invalid Python distribution pins for {name}.")
        if name in ("python-lsp-server", "clang-format"):
            if distributions.get(name) != record["version"] or "pip" not in distributions:
                raise RuntimeError(f"Missing Python reconstruction pins for {name}.")
        elif distributions:
            raise RuntimeError(f"Unexpected Python environment for {name}.")
    return records


def capture_tools(home):
    home = _home(home)
    records = {"format": 1, "root": ROOT, "architecture": platform.machine(),
               "tools": {name: _read_tool(home / ROOT, name) for name in SOURCES},
               "validation": "receipt, links, package content and installed Python metadata",
               "rebuild": "fixed registry/source versions; Python dependencies constrained to recorded versions"}
    return validate_records(records)


def _same(actual, expected):
    return all(actual.get(key) == expected.get(key) for key in
               ("source", "version", "registry", "raw_source_sha256", "links", "python_distributions"))


def _equivalent(root, name, record):
    try:
        actual = _read_tool(root, name)
        if not _same(actual, record):
            return False
        if actual["content_sha256"] == record["content_sha256"] and actual["receipt_sha256"] == record["receipt_sha256"]:
            return True
        proof = _json(root / "packages" / name / PROVENANCE)
        return (isinstance(proof, dict) and proof.get("record_sha256") == _object_hash(record) and
                proof.get("content_sha256") == actual["content_sha256"] and
                proof.get("receipt_sha256") == actual["receipt_sha256"])
    except (OSError, ValueError, KeyError, TypeError, RuntimeError):
        return False


def _targets(root, name, record):
    result = [root / "packages" / name]
    for kind, links in record["links"].items():
        result.extend(root / kind / link for link in links)
    for path in result:
        _parents(path.parent)
    return result


def _stage_identity(stage):
    helper = Path(__file__).with_name("nvim_state.py")
    spec = importlib.util.spec_from_file_location("_mason_nvim_state", helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = module.validated_stage_identity(stage)
    result["directory_identity"] = _directory_identity(stage)
    plugin = stage / "plugins/mason.nvim"
    result["mason_identity"] = _directory_identity(plugin)
    _parents(plugin / "lua/mason")
    entry = plugin / "lua/mason/init.lua"
    if entry.is_symlink() or not entry.is_file():
        raise RuntimeError("Validated stage lacks the Mason implementation.")
    result["validator_sha256"] = _hash(helper)
    return result


def _target_state(path, home):
    parents = {}
    for parent in path.parents:
        if not parent.is_relative_to(home):
            break
        parents[str(parent)] = _directory_identity(parent) if parent.exists() else None
    return {"identity": _path_identity(path), "content": _fingerprint(path), "parents": parents}


def _plan(home, records, stage_identity):
    root = home / ROOT
    tools = {}
    for name, record in records["tools"].items():
        same = _equivalent(root, name, record)
        tools[name] = {"status": "check" if same else "rebuild", "validated": False,
                       "version": record["version"], "source": record["source"],
                       "registry": record["registry"], "target": str(root / "packages" / name),
                       "paths": [str(p) for p in _targets(root, name, record)],
                       "reason": "matching receipt and content; functional check required" if same else "missing or different recorded tool"}
    plan = {"status": "preview", "validated": False, "root": str(root), "tools": tools,
            "network": any(v["status"] == "rebuild" for v in tools.values()),
            "build": "Mason official installers in isolated final-prefix mount; no system package installation",
            "preserve": str(home / "mason_restore_backup_<timestamp>_<id>"),
            "lock": str(home / ".mason-rebuild.lock"), "stage": stage_identity,
            "targets": {path: _target_state(Path(path), home) for tool in tools.values() for path in tool["paths"]},
            "limits": "Pinned sources and versions; rebuilt bytes can differ. Current system libraries remain external."}
    plan["identity"] = _object_hash({"plan": plan, "records": records, "helper_sha256": _hash(Path(__file__))})
    return plan


def _expect_plan(home, records, stage, identity):
    plan = _plan(home, records, _stage_identity(stage))
    if not SHA.fullmatch(str(identity)) or plan["identity"] != identity:
        raise RuntimeError("Mason reconstruction plan changed; preview and confirm the new identity.")
    return plan


def _unchanged_targets(states, home):
    for value, expected in states.items():
        if _target_state(Path(value), home) != expected:
            raise RuntimeError(f"Mason target or its parent changed after confirmation: {value}")


def _unchanged_stage(stage, expected):
    if _stage_identity(stage) != expected:
        raise RuntimeError("Staged Neovim payload changed after Mason confirmation.")


def _after_parent_creation(plan, home, parent):
    states = {path: _target_state(Path(path), home) for path in plan["targets"]}
    for path, expected in plan["targets"].items():
        actual = states[path]
        if any(actual[key] != expected[key] for key in ("identity", "content")):
            raise RuntimeError(f"Mason target changed after confirmation: {path}")
        for value, identity in expected["parents"].items():
            if actual["parents"][value] != identity and not (identity is None and parent.is_relative_to(Path(value))):
                raise RuntimeError(f"Mason parent changed after confirmation: {value}")
    return states


class _HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, url):
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname not in ("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"):
            raise RuntimeError("Untrusted Mason registry redirect.")
        return super().redirect_request(request, fp, code, message, headers, url)


def _registry_specs(registry, expected):
    url = "https://github.com/mason-org/mason-registry/releases/download/" + registry["version"] + "/registry.json.zip"
    request = urllib.request.Request(url, headers={"User-Agent": "nvim-mason-restore"})
    with urllib.request.build_opener(_HTTPSRedirect()).open(request, timeout=90) as response:
        archive = response.read(32 * 1024 * 1024 + 1)
    return _decode_registry(archive, registry, expected)


def _decode_registry(archive, registry, expected):
    if len(archive) > 32 * 1024 * 1024 or hashlib.sha256(archive).hexdigest() != registry["checksums"]["registry.json.zip"]:
        raise RuntimeError("Mason registry archive checksum mismatch.")
    with zipfile.ZipFile(io.BytesIO(archive)) as stream:
        members = stream.infolist()
        if len(members) != 1 or members[0].filename != "registry.json" or members[0].file_size > 64 * 1024 * 1024:
            raise RuntimeError("Unexpected Mason registry archive contents.")
        contents = stream.read(members[0])
    if hashlib.sha256(contents).hexdigest() != registry["checksums"]["registry.json"]:
        raise RuntimeError("Mason registry JSON checksum mismatch.")
    specifications = json.loads(contents)
    if not isinstance(specifications, list):
        raise RuntimeError("Invalid Mason registry JSON.")
    selected = {}
    for spec in specifications:
        if not isinstance(spec, dict):
            raise RuntimeError("Invalid Mason registry package definition.")
        name = spec.get("name")
        if name in expected:
            if name in selected or _object_hash(spec.get("source")) != expected[name]["raw_source_sha256"]:
                raise RuntimeError(f"Pinned registry and receipt source disagree for {name}.")
            if set(spec.get("bin", {})) != BIN_NAMES[name] or spec.get("opt"):
                raise RuntimeError(f"Unexpected registry links for {name}.")
            selected[name] = spec
    if set(selected) != set(expected):
        raise RuntimeError("Pinned registry lacks a required Mason tool.")
    return selected


INSTALL_LUA = r'''
local request = vim.json.decode(table.concat(vim.fn.readfile(arg[1]), '\n'))
vim.opt.runtimepath:prepend(request.plugin)
local registry = require('mason-registry')
require('mason').setup({install_root_dir=request.root, PATH='skip',
  registries={'file:' .. request.registry}, system_registries={},
  registry_cache={refresh=false}, firewall={auto_managed=false}, providers={'mason.providers.client'},
  pip={upgrade_pip=false, install_args=request.pip_args}})
local source = registry.sources:get(1):get()
assert(type(source.reload) == 'function', 'Mason file registry API is unavailable')
source:reload({request.spec})
local package = registry.get_package(request.name)
assert(package.spec.source.id == request.spec.source.id, 'Mason source changed')
if request.check_only then
  assert(type(package.install) == 'function', 'Mason install API is unavailable')
  print('Mason file registry API verified')
  return
end
local done, success, failure = false, false, nil
local handle = package:install({version=request.version, force=false, debug=true}, function(ok, result)
  done, success = true, ok
  if not ok then failure = tostring(result) end
end)
assert(handle and type(handle.is_closed) == 'function', 'Mason install handle is unavailable')
local finished = vim.wait(1800000, function() return done and handle:is_closed() end, 50)
if not finished then
  handle:terminate()
  vim.wait(10000, function() return done and handle:is_closed() end, 50)
  error('Mason installation timed out')
end
assert(success, failure or 'Mason installation failed')
print('Mason installation completed')
'''


PROBE_PYTHON = r'''
import json, os, pathlib, selectors, subprocess, sys, time
root=pathlib.Path(sys.argv[1]); wanted=json.loads(sys.argv[2]); results={}
def lsp(binary, language, text):
 p=subprocess.Popen([str(binary)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
 selector=selectors.DefaultSelector(); selector.register(p.stdout, selectors.EVENT_READ); buffered=b''
 def send(value):
  body=json.dumps(value).encode(); p.stdin.write(b'Content-Length: '+str(len(body)).encode()+b'\r\n\r\n'+body); p.stdin.flush()
 def receive(number):
  nonlocal buffered
  deadline=time.monotonic()+35
  while time.monotonic()<deadline:
   if b'\r\n\r\n' in buffered:
    head,body=buffered.split(b'\r\n\r\n',1)
    length=int(next(line.split(b':',1)[1] for line in head.split(b'\r\n') if line.lower().startswith(b'content-length:')))
    if len(body)>=length:
     buffered=body[length:]; value=json.loads(body[:length])
     if value.get('id')==number and ('result' in value or 'error' in value): return value
     continue
   if selector.select(max(0,deadline-time.monotonic())):
    chunk=os.read(p.stdout.fileno(),65536)
    if not chunk: raise RuntimeError('LSP exited before reply')
    buffered+=chunk
  raise RuntimeError('LSP request timed out')
 try:
  workspace=pathlib.Path.cwd(); path=workspace/('sample.cpp' if language=='cpp' else 'sample.py'); path.write_text(text)
  send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'processId':os.getpid(),'rootUri':workspace.as_uri(),'capabilities':{}}})
  first=receive(1)
  if 'error' in first or not first.get('result',{}).get('capabilities'): raise RuntimeError('LSP initialize failed')
  send({'jsonrpc':'2.0','method':'initialized','params':{}})
  send({'jsonrpc':'2.0','method':'textDocument/didOpen','params':{'textDocument':{'uri':path.as_uri(),'languageId':language,'version':1,'text':text}}})
  send({'jsonrpc':'2.0','id':2,'method':'textDocument/documentSymbol','params':{'textDocument':{'uri':path.as_uri()}}})
  second=receive(2)
  if 'error' in second or not second.get('result'): raise RuntimeError('LSP documentSymbol failed')
  send({'jsonrpc':'2.0','id':3,'method':'shutdown','params':None}); receive(3)
  send({'jsonrpc':'2.0','method':'exit','params':None}); p.wait(timeout=10)
  if p.returncode: raise RuntimeError('LSP exit failed')
 finally:
  selector.close()
  if p.poll() is None: p.kill(); p.wait()
  p.stdin.close(); p.stdout.close()
for name, record in wanted.items():
 binary=root/'bin'/record['binary']
 version=subprocess.run([str(binary),'--version'],capture_output=True,text=True,timeout=20,check=True).stdout.strip()
 expected=record['version'].lstrip('v')
 import re
 if not re.search(r'(?<![\w.])v?'+re.escape(expected)+r'(?![\w.])',version): raise RuntimeError(name+' version mismatch: '+version)
 if name=='clangd': lsp(binary,'cpp','int review_symbol() { return 3; }\n')
 elif name=='python-lsp-server': lsp(binary,'python','def review_symbol():\n    return 3\n')
 else:
  args=[str(binary),'--style=LLVM'] if name=='clang-format' else [str(binary),'-']
  sample='int main(){return 3;}\n' if name=='clang-format' else 'local review = {1,2}\n'
  result=subprocess.run(args,input=sample,capture_output=True,text=True,timeout=20,check=True)
  if not result.stdout.strip() or result.stdout==sample: raise RuntimeError(name+' format check failed')
 results[name]={'version_output':version.splitlines()[0], 'validation':'initialize/documentSymbol' if name in ('clangd','python-lsp-server') else 'format-stdin'}
print(json.dumps(results))
'''


def _env(work, home):
    env = {key: value for key, value in os.environ.items() if key in
           ("LANG", "LC_ALL", "http_proxy", "https_proxy", "all_proxy", "no_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY")}
    env.update(HOME=str(home), PATH="/usr/bin:/bin", PYTHONDONTWRITEBYTECODE="1", PYTHONNOUSERSITE="1",
               PIP_CONFIG_FILE="/dev/null", PIP_INDEX_URL="https://pypi.org/simple", PIP_DISABLE_PIP_VERSION_CHECK="1",
               XDG_CONFIG_HOME=str(work / "config"), XDG_DATA_HOME=str(work / "data"),
               XDG_CACHE_HOME=str(work / "cache"), XDG_STATE_HOME=str(work / "state"),
               TMPDIR=str(work / "tmp"), NVIM_LOG_FILE=str(work / "nvim.log"))
    return env


def _run(command, env, log=None, timeout=1900):
    result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=timeout)
    if log:
        log.write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Mason subprocess failed ({result.returncode}); " + (f"see {log}" if log else result.stderr.strip()[-2000:]))
    return result.stdout.strip()


def _sandbox(work, home, root=None, stage=None, network=False):
    command = ["bwrap", "--die-with-parent", "--unshare-pid", "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc"]
    if not network:
        command.append("--unshare-net")
    if root is not None:
        command += ["--tmpfs", str(home), "--bind", str(work), str(work)]
        if stage:
            command += ["--ro-bind", str(stage), str(stage)]
        command += ["--dir", str(home / ROOT), "--bind", str(root), str(home / ROOT)]
    else:
        command += ["--bind", str(work), str(work)]
    return command + ["--chdir", str(work), "--"]


def _probe(home, records, root=None, work=None):
    owned = None
    if work is None:
        work, owned = _temporary("mason-check-")
    try:
        (work / "tmp").mkdir(exist_ok=True)
        wanted = {name: {"version": record["version"], "binary": SOURCES[name][1]} for name, record in records.items()}
        command = _sandbox(work, home, root=root) + ["/usr/bin/python3", "-B", "-I", "-c", PROBE_PYTHON, str(home / ROOT), json.dumps(wanted)]
        return json.loads(_run(command, _env(work, work), timeout=240))
    finally:
        if owned is not None:
            try:
                _cleanup(work, owned)
            finally:
                os.close(owned["fd"])


def _install(home, work, stage, name, record, spec, check_only=False):
    for directory in ("config", "data", "cache", "state/nvim", "tmp"):
        (work / directory).mkdir(parents=True, exist_ok=True)
    request_path = work / (name + ".json")
    pins = record["python_distributions"]
    constraints = work / (name + "-constraints.txt")
    constraints.write_text("".join(f"{key}=={value}\n" for key, value in sorted(pins.items())), encoding="utf-8")
    request = {"root": str(home / ROOT), "plugin": str(stage / "plugins/mason.nvim"),
               "registry": str(work / "registry"), "name": name, "version": record["version"], "spec": spec,
               "check_only": check_only, "pip_args": (["--constraint", str(constraints)] +
                [f"{key}=={value}" for key, value in sorted(pins.items())]) if pins else []}
    _write(request_path, request)
    env = _env(work, home)
    env["VIMRUNTIME"] = str(stage / "runtime/share/nvim/runtime")
    command = _sandbox(work, home, root=work / "install", stage=stage, network=not check_only)
    command += [str(stage / "runtime/bin/nvim"), "--headless", "-u", "NONE", "-i", "NONE", "-n", "-l", str(work / "install.lua"), str(request_path)]
    _run(command, env, work / (name + ".log"))


def _rename(source, target, source_id=None, source_parent=None, target_parent=None):
    # RENAME_NOREPLACE also protects directory targets from races.
    libc = ctypes.CDLL(None, use_errno=True)
    if not hasattr(libc, "renameat2"):
        raise RuntimeError("Mason publication requires Linux renameat2.")
    source_fd = _directory_fd(source.parent)
    try:
        target_fd = _directory_fd(target.parent)
        try:
            if ((source_parent is not None and _identity(os.fstat(source_fd)) != source_parent) or
                    (target_parent is not None and _identity(os.fstat(target_fd)) != target_parent) or
                    (source_id is not None and _identity(os.stat(source.name, dir_fd=source_fd, follow_symlinks=False)) != source_id)):
                raise RuntimeError(f"Mason publication identity changed: {source} -> {target}")
            if libc.renameat2(source_fd, os.fsencode(source.name), target_fd, os.fsencode(target.name), 1):
                error = ctypes.get_errno()
                raise OSError(error, os.strerror(error), str(target))
        finally:
            os.close(target_fd)
    finally:
        os.close(source_fd)


def _publish(root, install, targets, before, safety, moved=None):
    moved = [] if moved is None else moved
    try:
        for target in targets:
            expected = before[str(target)]
            if _path_identity(target) != expected["identity"] or _fingerprint(target) != expected["content"]:
                raise RuntimeError(f"Mason target changed during reconstruction: {target}")
            relative = target.relative_to(root)
            saved = safety / "original" / relative
            failed = safety / "failed" / relative
            source = install / relative
            if not _exists(source):
                raise RuntimeError(f"Incomplete Mason publication payload: {source}")
            moved.append({"target": str(target), "saved": str(saved), "source": str(source), "failed": str(failed),
                          "original": expected["identity"], "original_content": expected["content"],
                          "installed": _path_identity(source), "installed_content": _fingerprint(source),
                          "target_parent": _directory_identity(target.parent, create=True),
                          "saved_parent": _directory_identity(saved.parent, create=True),
                          "failed_parent": _directory_identity(failed.parent, create=True),
                          "source_parent": _directory_identity(source.parent),
                          "safety_identity": _directory_identity(safety)})
        _write(safety / ("transaction-" + uuid.uuid4().hex + ".json"), moved)
        with _termination_guard():
            for entry in moved:
                target, saved, source = (Path(entry[key]) for key in ("target", "saved", "source"))
                if _path_identity(target) != entry["original"] or _fingerprint(target) != entry["original_content"]:
                    raise RuntimeError(f"Mason target changed before publication: {target}")
                if entry["original"] is not None:
                    _rename(target, saved, entry["original"], entry["target_parent"], entry["saved_parent"])
                    if _fingerprint(saved) != entry["original_content"]:
                        raise RuntimeError(f"Mason target changed during preservation: {target}")
                _rename(source, target, entry["installed"], entry["source_parent"], entry["target_parent"])
        return moved
    except BaseException:
        _rollback(moved, root, safety)
        raise


def _rollback(moved, root, safety):
    retained = []
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM, signal.SIGHUP})
    try:
        for entry in reversed(moved):
            target, saved, failed = (Path(entry[key]) for key in ("target", "saved", "failed"))
            try:
                for path, key in ((target.parent, "target_parent"), (saved.parent, "saved_parent"),
                                  (failed.parent, "failed_parent"), (safety, "safety_identity")):
                    if _directory_identity(path) != entry[key]:
                        raise RuntimeError(f"Mason rollback parent changed: {path}")
                actual = _path_identity(target)
                if actual == entry["installed"]:
                    if _fingerprint(target) != entry["installed_content"]:
                        raise RuntimeError(f"Mason installed content changed; retained: {target}")
                    _rename(target, failed, entry["installed"], entry["target_parent"], entry["failed_parent"])
                    actual = None
                if entry["original"] is not None and actual is None:
                    if _path_identity(saved) != entry["original"]:
                        raise RuntimeError(f"Mason preserved original is unavailable: {saved}")
                    _rename(saved, target, entry["original"], entry["saved_parent"], entry["target_parent"])
                elif actual != entry["original"]:
                    retained.append(str(target))
            except (OSError, RuntimeError) as error:
                retained.append(f"{target}: {error}")
        if retained and moved and _directory_identity(safety) == moved[0]["safety_identity"]:
            _write(safety / ("rollback-" + uuid.uuid4().hex + ".json"), {"retained_changes": retained})
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
    return retained


@contextmanager
def _locked(home):
    path = home / ".mason-rebuild.lock"
    parent_fd = _directory_fd(home)
    try:
        descriptor = os.open(path.name, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600, dir_fd=parent_fd)
    finally:
        os.close(parent_fd)
    with os.fdopen(descriptor, "w") as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another Mason reconstruction is running.") from None
        yield


def restore_tools(home, records, staged_source, lua_helper=None, execute=False, expect_identity=None):
    home = _home(home)
    records = validate_records(records)
    stage = Path(staged_source).absolute()
    plan = _plan(home, records, _stage_identity(stage))
    if not execute:
        return plan
    if not SHA.fullmatch(str(expect_identity)) or plan["identity"] != expect_identity:
        raise RuntimeError("Mason execution requires the unchanged preview identity; preview and confirm again.")
    if os.geteuid() == 0 or home.stat().st_uid != os.geteuid() or Path.home() != home:
        raise RuntimeError("Run Mason reconstruction as the target home owner, with its HOME.")
    if not shutil.which("bwrap"):
        raise RuntimeError("Mason reconstruction and functional checks require bubblewrap.")
    root = home / ROOT
    rebuild = {name: records["tools"][name] for name, result in plan["tools"].items() if result["status"] == "rebuild"}
    if not rebuild:
        _expect_plan(home, records, stage, expect_identity)
        probes = _probe(home, records["tools"])
        _unchanged_stage(stage, plan["stage"])
        _unchanged_targets(plan["targets"], home)
        for name, result in plan["tools"].items():
            if not _equivalent(root, name, records["tools"][name]):
                raise RuntimeError(f"Mason content changed during functional verification: {name}")
            result.update(status="skipped", validated=True, reason="matching receipt/content and functional checks", **probes[name])
        plan.update(status="verified", validated=True)
        return plan
    with _locked(home), _termination_guard():
        _expect_plan(home, records, stage, expect_identity)
        targets = [target for name, record in rebuild.items() for target in _targets(root, name, record)]
        for name in rebuild:
            for path in (root / "staging" / name, root / "staging" / (name + ".lock")):
                if _exists(path):
                    raise RuntimeError(f"Existing Mason staging work must be reviewed first: {path}")
        _directory_identity(root.parent, create=True)
        work, owned = _temporary(".mason-rebuild-", root.parent)
        safety = home / ("mason_restore_backup_" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ_") + uuid.uuid4().hex[:8])
        moved = []
        try:
            before = _after_parent_creation(plan, home, root.parent)
            for name in ("install", "tmp", "registry"):
                (work / name).mkdir()
            (work / "install.lua").write_text(INSTALL_LUA, encoding="utf-8")
            registries = {}
            for record in rebuild.values():
                key = _object_hash(record["registry"])
                registries[key] = record["registry"]
            specs = {}
            for key, registry in registries.items():
                _unchanged_stage(stage, plan["stage"])
                _unchanged_targets(before, home)
                subset = {name: record for name, record in rebuild.items() if _object_hash(record["registry"]) == key}
                specs.update(_registry_specs(registry, subset))
            for name, record in rebuild.items():
                _unchanged_stage(stage, plan["stage"])
                _unchanged_targets(before, home)
                _install(home, work, stage, name, record, specs[name])
                package = work / "install/packages" / name
                receipt = _json(package / "mason-receipt.json")
                if receipt.get("source", {}).get("id") != record["source"] or _object_hash(receipt["source"]["raw"]) != record["raw_source_sha256"]:
                    raise RuntimeError(f"Rebuilt Mason source does not match {name}.")
                if _links(name, receipt["links"]) != record["links"] or _distributions(package) != record["python_distributions"]:
                    raise RuntimeError(f"Rebuilt Mason links or Python dependencies differ for {name}.")
                _write(package / PROVENANCE, {"format": 1, "source": record["source"], "registry": record["registry"],
                       "record_sha256": _object_hash(record), "receipt_sha256": _hash(package / "mason-receipt.json"),
                       "content_sha256": _tree_hash(package, payload=True)})
                if not _same(_read_tool(work / "install", name), record):
                    raise RuntimeError(f"Rebuilt Mason receipt or links differ for {name}.")
            _probe(home, rebuild, root=work / "install", work=work)
            _unchanged_stage(stage, plan["stage"])
            _unchanged_targets(before, home)
            safety.mkdir(mode=0o700)
            _write(safety / "plan.json", plan)
            _publish(root, work / "install", targets, before, safety, moved)
            probes = _probe(home, records["tools"])
            _unchanged_stage(stage, plan["stage"])
            for entry in moved:
                target = Path(entry["target"])
                if (_directory_identity(target.parent) != entry["target_parent"] or
                        _path_identity(target) != entry["installed"] or _fingerprint(target) != entry["installed_content"]):
                    raise RuntimeError(f"Mason publication changed during final verification: {target}")
            untouched = {path: before[path] for name, tool in plan["tools"].items() if name not in rebuild for path in tool["paths"]}
            _unchanged_targets(untouched, home)
            for name, result in plan["tools"].items():
                if not _equivalent(root, name, records["tools"][name]):
                    raise RuntimeError(f"Mason content changed during final verification: {name}")
                result.update(status="verified" if name in rebuild else "skipped", validated=True,
                              reason="verified pinned reconstruction" if name in rebuild else "matching receipt/content and functional checks", **probes[name])
            plan.update(status="verified", validated=True, safety_backup=str(safety))
            _write(safety / "result.json", plan)
            _cleanup(work, owned)
            return plan
        except BaseException as error:
            safety.mkdir(mode=0o700, exist_ok=True)
            if moved:
                _rollback(moved, root, safety)
            if _path_identity(work) == owned["identity"]:
                _rename(work, safety / "diagnostics", owned["identity"], owned["parent"], _directory_identity(safety))
            elif _exists(work):
                error = RuntimeError(f"{error}; temporary path was replaced and retained: {work}")
            _write(safety / ("failure-" + uuid.uuid4().hex + ".json"), {"status": "failed", "validated": False, "error": str(error)})
            raise RuntimeError(f"Mason reconstruction failed; originals/diagnostics retained at {safety}: {error}") from error
        finally:
            os.close(owned["fd"])
