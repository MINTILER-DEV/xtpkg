"""Deterministic integration tests using the actual LuauXTX CLI and local Git.

Run: python -u tests/run.py [--runtime /path/to/luauxtx]
No public registry, GitHub credentials, or third-party Python modules required.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--runtime", default=shutil.which("luauxtx"))
args = parser.parse_args()
if not args.runtime:
    raise SystemExit("LuauXTX is required; pass --runtime /path/to/luauxtx")
runtime = str(Path(args.runtime).resolve())
if Path(runtime).suffix.lower() in (".cmd", ".bat"):
    probe = subprocess.run([runtime, str(ROOT / "tests/runtime-probe.luau")],
                           cwd=ROOT, text=True, encoding="utf-8", errors="replace",
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    candidate = Path(probe.stdout.strip())
    if probe.returncode != 0 or not candidate.is_file() or candidate.suffix.lower() != ".exe":
        raise SystemExit("Pass --runtime with the native LuauXTX executable; the launcher shim could not be resolved")
    runtime = str(candidate)
checks = 0
unit_checks = 0
started = time.monotonic()


def check(value, detail="check failed"):
    global checks
    checks += 1
    assert value, detail


def execute(command, cwd, env=None, ok=True):
    result = subprocess.run(command, cwd=cwd, env=env, text=True,
                            encoding="utf-8", errors="replace",
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=180)
    check((result.returncode == 0) == ok, f"{command}\n{result.stdout}")
    if not ok:
        check("stack traceback:" not in result.stdout, result.stdout)
    return result.stdout


def git(cwd, *arguments):
    return execute(["git", "-c", "core.hooksPath=", *arguments], cwd).strip()


def write(p, text):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8", newline="")


def canonical(data):
    return json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


with tempfile.TemporaryDirectory(prefix="xtpkg-tests-") as temporary:
    base = Path(temporary)
    app, registry, cache, config = [base / n for n in ("app", "registry", "cache", "config")]
    for d in (app, registry, config):
        d.mkdir()
    env = dict(os.environ, XTPKG_REGISTRY=str(registry), XTPKG_CACHE_DIR=str(cache),
               XTPKG_CONFIG_HOME=str(config), GIT_TERMINAL_PROMPT="0")

    def cli(*arguments, cwd=app, ok=True, environment=None):
        return execute([runtime, str(ROOT / "src/main.luau"), *arguments], cwd,
                       environment or env, ok)

    def luau(script, cwd=app, ok=True):
        return execute([runtime, str(script)], cwd, env, ok)

    for name in ("core", "resolver", "security", "registry-client"):
        print(f"Running {name} checks...", flush=True)
        report = luau(ROOT / f"tests/{name}.luau").strip()
        print(report, flush=True)
        unit_checks += int(re.search(r"passed: (\d+)", report).group(1))

    def package(name, version, contents, dependencies=None, repository=None):
        repo = repository or base / name.replace("/", "-")
        repo.mkdir(exist_ok=True)
        if not (repo / ".git").exists():
            git(repo, "init", "-q")
            git(repo, "config", "user.name", "XTPKG Test")
            git(repo, "config", "user.email", "xtpkg-test@example.invalid")
            git(repo, "config", "core.autocrlf", "false")
        deps = dependencies or {}
        manifest = (f'[package]\nname = "{name}"\nversion = "{version}"\n'
                    'entry = "init.luau"\ndescription = "Fixture package"\n'
                    'license = "MIT"\nrepository = "https://example.invalid/repository"\n'
                    '[dependencies]\n' + "".join(f'{json.dumps(k)} = {json.dumps(v)}\n' for k, v in deps.items()))
        write(repo / "xtpkg.toml", manifest)
        write(repo / "init.luau", contents)
        write(repo / "LICENSE", "Test fixture licence.\n")
        git(repo, "add", ".")
        git(repo, "commit", "-qm", f"Fixture {version}")
        revision = git(repo, "rev-parse", "HEAD")
        files = {n: (repo / n).read_text(encoding="utf-8") for n in ("xtpkg.toml", "init.luau", "LICENSE")}
        integrity = hashlib.sha256(canonical(files).encode()).hexdigest()
        return repo, {"source": {"type": "git", "url": str(repo), "revision": revision},
                      "entry": "init.luau", "integrity": integrity, "dependencies": deps}

    core_repo, core_v1 = package("ex/core", "1.0.0", "return { value = 41 }\n")
    json_repo, json_v1 = package("ex/json", "1.0.0", 'local core = require("../core")\nreturn { value = core.value + 1 }\n', {"ex/core": "^1.0.0"})
    data = {
        "ex/core": {"name": "ex/core", "description": "Core fixture", "repository": "https://example.invalid/core", "versions": {"1.0.0": core_v1}},
        "ex/json": {"name": "ex/json", "description": "JSON fixture", "repository": "https://example.invalid/json", "versions": {"1.0.0": json_v1}},
    }

    def save_registry():
        index = {"registry_version": 1, "packages": {}}
        for name, metadata in data.items():
            relative = f"packages/{name}.json"
            index["packages"][name] = {"path": relative, "description": metadata["description"]}
            write(registry / relative, canonical(metadata))
        write(registry / "index.json", canonical(index))

    save_registry()
    print("Testing CLI, registry, and exact Git installation...", flush=True)
    check("0.2.0" in cli("--version"))
    check("Usage: xtpkg add" in cli("help", "add"))
    check("Unknown command" in cli("no-such-command", ok=False))
    check("Unknown option" in cli("install", "--invalid", ok=False))
    cli("init", "app")
    write(app / "xtpkg.toml", (app / "xtpkg.toml").read_text() + 'probe = "echo XTPKG_RUN_OK"\n\n[custom]\nitems = [1, 2]\n# preserve me\n')
    check("XTPKG_RUN_OK" in cli("run", "probe"))
    check("Script not found" in cli("run", "missing", ok=False))
    original_manifest = (app / "xtpkg.toml").read_bytes()
    check("not found" in cli("add", "ex/jsno", ok=False))
    check((app / "xtpkg.toml").read_bytes() == original_manifest)
    check("Local Git fixtures" in cli("add", "ex/json@^1.0.0", ok=False))
    cli("add", "ex/json@^1.0.0", "--allow-local-sources")
    check((app / "packages/ex/json/init.luau").exists())
    check((app / "packages/ex/core/init.luau").exists())
    check("items = [1, 2]" in (app / "xtpkg.toml").read_text())
    check("ex/core" in cli("list", "--tree"))
    check("ex/json" in cli("search", "json"))
    check("1.0.0" in cli("info", "ex/json", "--allow-local-sources"))
    check("up to date" in cli("outdated", "--allow-local-sources"))
    write(app / "import-test.luau", 'local imports = require("./packages/.xtpkg-imports")\nassert(imports.require("ex/json").value == 42)\nassert(require("./packages/ex/json").value == 42)\nprint("IMPORT_OK")\n')
    check("IMPORT_OK" in luau(app / "import-test.luau"))
    lock_v1 = (app / "xtpkg.lock").read_bytes()
    cli("install", "--locked", "--allow-local-sources")
    check((app / "xtpkg.lock").read_bytes() == lock_v1)

    print("Testing update, lock reuse, frozen and offline behavior...", flush=True)
    _, core_v2 = package("ex/core", "1.1.0", "return { value = 42 }\n", repository=core_repo)
    _, json_v2 = package("ex/json", "1.1.0", 'local core = require("../core")\nreturn { value = core.value + 1 }\n', {"ex/core": "^1.0.0"}, json_repo)
    data["ex/core"]["versions"]["1.1.0"] = core_v2
    data["ex/json"]["versions"]["1.1.0"] = json_v2
    save_registry()
    cli("install", "--allow-local-sources")
    check((app / "xtpkg.lock").read_bytes() == lock_v1, "normal install upgraded a locked package")
    check("1.1.0" in cli("outdated", "--allow-local-sources"))
    cli("update", "ex/json", "--allow-local-sources")
    lock_target = (app / "xtpkg.lock").read_text()
    check('version = "1.1.0"' in lock_target and 'version = "1.0.0"' in lock_target, lock_target)
    cli("update", "--allow-local-sources")
    lock_v2 = (app / "xtpkg.lock").read_bytes()
    check(lock_v1 != lock_v2)
    check("Verified" in cli("cache", "verify"))
    check(cache.as_posix().lower() in cli("cache", "path").replace("\\", "/").lower())
    check("packages" in cli("cache", "list"))
    registry.rename(base / "registry-away")
    core_repo.rename(base / "core-away")
    json_repo.rename(base / "json-away")
    shutil.rmtree(app / "packages")
    frozen_env = dict(env, XTPKG_REGISTRY="https://network-must-not-be-used.invalid/registry")
    cli("install", "--frozen", "--allow-local-sources", environment=frozen_env)
    check((app / "xtpkg.lock").read_bytes() == lock_v2)
    cli("install", "--offline", "--allow-local-sources")
    check((app / "xtpkg.lock").read_bytes() == lock_v2)
    check("ex/json" in cli("search", "json", "--offline"))
    # Resolution, rather than lock reproduction, must use only cached metadata.
    (app / "xtpkg.lock").unlink()
    cli("install", "--offline", "--allow-local-sources")
    check((app / "xtpkg.lock").read_bytes() == lock_v2)
    (base / "registry-away").rename(registry)
    (base / "core-away").rename(core_repo)
    (base / "json-away").rename(json_repo)

    print("Testing corrupted/missing artifacts and failed downloads...", flush=True)
    artifacts = list((cache / "packages").glob("*.json"))
    target = next(p for p in artifacts if json.loads(json.loads(p.read_text())["key"])["version"] == "1.1.0" and json.loads(json.loads(p.read_text())["key"])["name"] == "ex/json")
    saved = target.read_bytes()
    write(target, target.read_text().replace("core.value + 1", "core.value + 9"))
    check("Corrupted" in cli("cache", "verify", ok=False))
    check("Corrupted" in cli("install", "--frozen", "--allow-local-sources", ok=False))
    check((app / "xtpkg.lock").read_bytes() == lock_v2)
    target.write_bytes(saved)
    # A valid envelope checksum must not mask corrupted package contents.
    envelope = json.loads(saved)
    envelope["data"]["files"]["init.luau"] += "-- tampered\n"
    envelope["checksum"] = hashlib.sha256(canonical(envelope["data"]).encode()).hexdigest()
    write(target, canonical(envelope))
    check("integrity mismatch" in cli("cache", "verify", ok=False))
    target.write_bytes(saved)
    target.unlink()
    check("missing" in cli("install", "--frozen", "--allow-local-sources", ok=False))
    target.write_bytes(saved)
    manifest_before = (app / "xtpkg.toml").read_bytes()
    bad = json.loads(canonical(data["ex/json"]))
    bad["name"] = "ex/bad"
    bad["versions"] = {"1.0.0": dict(json_v1, source={"type": "git", "url": str(base / "does-not-exist"), "revision": "a" * 40})}
    data["ex/bad"] = bad
    save_registry()
    check("Git operation failed" in cli("add", "ex/bad", "--allow-local-sources", ok=False))
    check((app / "xtpkg.toml").read_bytes() == manifest_before)
    check((app / "xtpkg.lock").read_bytes() == lock_v2)
    check((app / "packages/ex/json/init.luau").exists())
    check(not list(app.glob(".xtpkg-stage-*")))
    check(not (app / ".xtpkg-operation").exists())

    print("Testing transaction rollback and dependency removal...", flush=True)
    rollback_script = base / "rollback.luau"
    write(rollback_script, f'''local fs = require("system/fs")
local Promise = require("async/promise")
local Operations = require({json.dumps((ROOT / "src/package/Operations").as_posix())})
local original = fs.rename
local injected = false
fs.rename = function(from, to)
    if not injected and to:sub(-10) == "xtpkg.lock" and from:find(".xtpkg-stage-", 1, true) then
        injected = true
        return Promise.reject("injected transaction failure")
    end
    return original(from, to)
end
local ok, err = pcall(function() Operations.perform({{ ["allow-local-sources"] = true }}, nil, true) end)
fs.rename = original
assert(injected and not ok and tostring(err):find("injected transaction failure", 1, true))
print("ROLLBACK_OK")
''')
    # Absolute require is supported by native LuauXTX.
    check("ROLLBACK_OK" in luau(rollback_script))
    check((app / "xtpkg.toml").read_bytes() == manifest_before)
    check((app / "xtpkg.lock").read_bytes() == lock_v2)
    check((app / "packages/ex/json/init.luau").exists())
    cli("remove", "ex/json", "--allow-local-sources")
    check(not (app / "packages/ex/json").exists())
    check(not (app / "packages/ex/core").exists())
    check("No dependencies" in cli("list"))

    print("Testing path dependency compatibility and manifest changes...", flush=True)
    local_repo, _ = package("localdep", "1.0.0", "return { localValue = 7 }\n")
    cli("add", f"path:{local_repo}")
    write(app / "local-test.luau", 'assert(require("./packages/localdep").localValue == 7)\n')
    luau(app / "local-test.luau")
    old_lock = (app / "xtpkg.lock").read_bytes()
    write(app / "xtpkg.toml", (app / "xtpkg.toml").read_text().replace('"localdep" =', '"localdep2" ='))
    check("requires an existing current" in cli("install", "--locked", ok=False))
    check((app / "xtpkg.lock").read_bytes() == old_lock)
    write(app / "xtpkg.toml", (app / "xtpkg.toml").read_text().replace('"localdep2" =', '"localdep" ='))
    cli("remove", "localdep", "--offline")

    print("Testing malformed/immutable metadata and Git symlink rejection...", flush=True)
    saved_index = (registry / "index.json").read_bytes()
    write(registry / "index.json", '{"registry_version":1,"packages":{},"packages":{}}')
    check("Malformed" in cli("search", ok=False))
    (registry / "index.json").write_bytes(saved_index)
    old_revision = data["ex/json"]["versions"]["1.1.0"]["source"]["revision"]
    data["ex/json"]["versions"]["1.1.0"]["source"]["revision"] = "a" * 40
    save_registry()
    check("immutable version" in cli("info", "ex/json", "--allow-local-sources", ok=False))
    data["ex/json"]["versions"]["1.1.0"]["source"]["revision"] = old_revision
    save_registry()
    link_repo, link_record = package("ex/link", "1.0.0", "return {}\n")
    write(base / "symlink-target.txt", "../outside")
    blob = git(link_repo, "hash-object", "-w", str(base / "symlink-target.txt"))
    git(link_repo, "update-index", "--add", "--cacheinfo", "120000", blob, "escape")
    git(link_repo, "commit", "-qm", "Fixture unsafe symlink")
    link_record["source"]["revision"] = git(link_repo, "rev-parse", "HEAD")
    data["ex/link"] = {"name": "ex/link", "description": "Unsafe fixture", "repository": "https://example.invalid/link", "versions": {"1.0.0": link_record}}
    save_registry()
    before_unsafe_add = (app / "xtpkg.toml").read_bytes()
    check("symlink" in cli("add", "ex/link", "--allow-local-sources", ok=False))
    check((app / "xtpkg.toml").read_bytes() == before_unsafe_add)
    # No administrator symlink permission is required for a Windows junction.
    outside = base / "outside"
    outside.mkdir()
    write(outside / "sentinel.txt", "keep me")
    junction = local_repo / "escape"
    if os.name == "nt":
        link_env = dict(env, XTPKG_LINK_PATH=str(junction), XTPKG_LINK_TARGET=str(outside))
        execute(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
                 "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:XTPKG_LINK_PATH -Target $env:XTPKG_LINK_TARGET | Out-Null"], base, link_env)
    else:
        junction.symlink_to(outside, target_is_directory=True)
    try:
        check("unsafe links" in cli("add", f"path:{local_repo}", ok=False))
        check((outside / "sentinel.txt").read_text() == "keep me")
    finally:
        junction.rmdir() if os.name == "nt" else junction.unlink()

    print("Testing legacy lock migration and unmanaged-directory preservation...", flush=True)
    legacy = base / "legacy"
    legacy.mkdir()
    cli("init", "legacy", cwd=legacy)
    write(legacy / "xtpkg.toml", (legacy / "xtpkg.toml").read_text().replace("[dependencies]", f'[dependencies]\nlocaldep = "path:{local_repo.as_posix()}"'))
    write(legacy / "xtpkg.lock", f'lock_version = 1\n\n[packages.localdep]\nsource = "path:{local_repo.as_posix()}"\nversion = "1.0.0"\n')
    shutil.copytree(local_repo, legacy / "packages/localdep", ignore=shutil.ignore_patterns(".git"))
    check("requires an existing current" in cli("install", "--locked", cwd=legacy, ok=False))
    cli("install", cwd=legacy)
    check((legacy / "xtpkg.lock").read_text().startswith("lock_version = 2"))
    check((legacy / "packages/localdep.luau").exists())
    unmanaged = base / "unmanaged-project"
    unmanaged.mkdir()
    cli("init", "unmanaged", cwd=unmanaged)
    write(unmanaged / "packages/keep.txt", "keep me")
    check("unmanaged packages" in cli("install", cwd=unmanaged, ok=False))
    check((unmanaged / "packages/keep.txt").read_text() == "keep me")

    print("Testing publishing validation and config...", flush=True)
    before = {p.relative_to(json_repo).as_posix(): p.read_bytes() for p in json_repo.rglob("*") if p.is_file() and ".git" not in p.parts}
    check("Dry run complete" in cli("publish", "--dry-run", cwd=json_repo))
    after = {p.relative_to(json_repo).as_posix(): p.read_bytes() for p in json_repo.rglob("*") if p.is_file() and ".git" not in p.parts}
    check(before == after)
    cli("publish", "--output", "submission.json", cwd=json_repo)
    submission = json.loads((json_repo / "submission.json").read_text())
    check(submission["versions"]["1.1.0"]["source"]["revision"] == json_v2["source"]["revision"])
    check(submission["versions"]["1.1.0"]["integrity"] == json_v2["integrity"])
    production = base / "production-registry"
    previous = base / "previous-registry"
    write(production / "index.json", canonical({"registry_version": 1, "packages": {"ex/json": {"path": "packages/ex/json.json"}}}))
    write(production / "packages/ex/json.json", canonical(submission))
    shutil.copytree(production, previous)
    check("Validated 1" in execute([runtime, str(ROOT / "tools/validate-registry.luau"), str(production), str(previous)], base, env))
    submission["versions"]["1.1.0"]["source"]["revision"] = "b" * 40
    write(production / "packages/ex/json.json", canonical(submission))
    check("Immutable version" in execute([runtime, str(ROOT / "tools/validate-registry.luau"), str(production), str(previous)], base, env, ok=False))
    (json_repo / "submission.json").unlink()
    check("sensitive package file" in cli("publish", "--output", ".git/hooks/unsafe", cwd=json_repo, ok=False))
    write(json_repo / "untracked.txt", "not committed")
    check("clean Git" in cli("publish", "--dry-run", cwd=json_repo, ok=False))
    (json_repo / "untracked.txt").unlink()
    check("Publishing requires package.description" in cli("publish", "--dry-run", ok=False))
    cli("config", "set", "registry", str(registry))
    no_override = dict(env)
    del no_override["XTPKG_REGISTRY"]
    check(registry.as_posix().lower() in cli("config", "get", "registry", environment=no_override).replace("\\", "/").lower())
    cli("config", "set", "registry", str(registry))  # atomic overwrite
    unmanaged_cache = base / "unmanaged-cache"
    unmanaged_cache.mkdir()
    write(unmanaged_cache / "sentinel.txt", "keep me")
    unmanaged_env = dict(env, XTPKG_CACHE_DIR=str(unmanaged_cache))
    check("Unmanaged" in cli("cache", "clean", environment=unmanaged_env, ok=False))
    check((unmanaged_cache / "sentinel.txt").read_text() == "keep me")
    check("Removed" in cli("cache", "clean"))
    check("Verified 0" in cli("cache", "verify"))
    check("metadata is missing" in cli("search", "--offline", ok=False))

print(f"PASS: {checks} integration assertions; {unit_checks} unit assertions. {time.monotonic() - started:.1f}s", flush=True)
