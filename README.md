# XTPKG

XTPKG is a LuauXTX package manager with local path dependencies, an approval-based
Git registry, deterministic SemVer resolution, verified caching, and reproducible
installations. The implementation is Luau and uses LuauXTX's existing filesystem,
HTTP, crypto, and process APIs. It never runs package install hooks.

Requires a current native **LuauXTX** runtime and **Git** on PATH. Link checks
currently use Windows PowerShell on Windows, or `sh` and `find` on Unix. Python
3.10+ is needed only for the integration test runner.

Run the CLI from a project directory:

```powershell
luauxtx D:/GitHub/Repositories/xtpkg/src/main.luau init my-app
```

The examples below use `xtpkg` as shorthand for that invocation. No executable
installer or global command is silently installed by this repository.

## Project manifest

```toml
[package]
name = "my-app"
version = "0.1.0"
entry = "src/main.luau"
description = "My application"
license = "MIT"
repository = "https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY"

[dependencies]
"example/json" = "^1.2.0"
localutil = "path:../localutil"

[scripts]
start = "luauxtx src/main.luau"
```

Description, license, and repository are optional for private projects and
required for publishing. Names may be `name` or `scope/name`, with lowercase
ASCII letters, digits, hyphens, and underscores. Unsafe Windows device names
are rejected on every platform. Entries must be relative `.lua`/`.luau` paths.

The supported manifest sections contain scalar TOML values; dependency and
script values must be quoted strings. Basic/literal strings, comments, and
quoted dependency keys are supported. Multiline strings, inline dependency
tables, and arrays in these three sections are unsupported and rejected.
Other tables and their values are retained when editing dependencies. Existing
package metadata, scripts, and unrelated text are preserved; dependency keys
are sorted when their section is edited. `local/testproj` remains an ignored
local project and is never a registry.

## Commands

| Command | Behavior |
| --- | --- |
| `init [name] [--force]` | Create a manifest and `src/main.luau` |
| `add name[@range]` | Resolve, install, and save a registry dependency |
| `add path:../package` | Install a local package, inferring its declared name |
| `add name@path:../package` | Install a local package with an identity check |
| `add name@git+https://host/repo#COMMIT --allow-git` | Explicit external Git dependency; COMMIT must be 40 lowercase hex characters |
| `remove name` | Remove a direct dependency and prune unused packages |
| `install` | Reproduce the current lock; resolve if roots changed or a lock is absent/legacy |
| `install --locked` | Require a valid matching v2 lock; allow downloads, forbid lock changes |
| `install --frozen` | Require a valid matching v2 lock; no registry/resolution/network; use verified cached artifacts only |
| `install --offline` | No network or source downloads; may resolve using cached registry metadata |
| `update [name]` | Update within declared ranges; preserve other compatible locked versions for a targeted update |
| `list [--tree]` | Show direct dependencies or resolved dependency relationships |
| `search [term]` | Search registry names and descriptions using its index |
| `info name` | Show metadata, versions, and immutable revisions |
| `outdated` | Show current, highest range-compatible, and latest stable versions |
| `publish [--dry-run] [--output file]` | Validate a clean committed package and prepare a registry PR submission |
| `cache path/list/verify/clean` | Inspect, verify, or remove managed cache entries |
| `config get registry` | Show the effective registry |
| `config set registry URL` | Persist an HTTPS registry base or absolute local directory |
| `run script` | Execute an explicitly selected script from the project manifest |
| `help [command]`, `version`, `--version` | Usage and version information |

Global options: `--help`/`-h`, `--verbose`/`-v`, `--quiet`/`-q`, `--offline`.
`--quiet` suppresses progress; requested data and errors still print. Verbose
mode includes diagnostic tracebacks. Ordinary command errors return status 1
without a traceback. Argument-count and unsupported-option errors are checked.
`run` intentionally executes a user-selected project shell command, never
dependency scripts. The manifest schema does not accept install hooks.

Use shell quoting for version ranges, especially `<`, `>`, and `^` in shells
where they have special meanings. Examples: `xtpkg add 'example/json@^1.2.0'`.
Some third-party `.cmd` launchers strip carets while forwarding arguments. Use
the native LuauXTX executable directly if a saved range loses its `^`; the test
runner resolves such launchers to their native executable before argument tests.

## Registry setup

There is **no default production registry**. Start with the empty template in
[`registry/`](registry/README.md), or create a GitHub repository with this layout:

```text
index.json
packages/example/json.json
```

Configure its raw content base URL, replacing the account, repository, and branch:

```text
xtpkg config set registry https://raw.githubusercontent.com/YOUR_ACCOUNT/YOUR_REGISTRY/YOUR_BRANCH
xtpkg search json
xtpkg add example/json
```

`XTPKG_REGISTRY` overrides saved configuration. A local registry directory works
without a web server. HTTPS Git sources work from either registry type. For
fully local fixtures, metadata may use an **absolute local Git repository path**
as its source URL only when the registry itself is local and the command has
`--allow-local-sources`. This opt-in is also required to reinstall such locks,
including in offline/frozen mode. Remote registries cannot activate this feature.

Index schema:

```json
{
  "registry_version": 1,
  "packages": {
    "example/json": {
      "path": "packages/example/json.json",
      "description": "JSON utilities"
    }
  }
}
```

Each metadata record has `name`, `description`, `repository`, and a `versions`
object. Each version has `source = { type: "git", url, revision }`, dependencies
as version-range strings, and optional `entry` and `integrity`. Revisions must
be full immutable Git commits; a tag/ref without a commit is rejected. Publishing
generates the exact record, including a checksum, so no illustrative fake
revision needs to be copied. Registry and external Git packages can depend only
on registry version ranges. Local private packages may use paths too.

Configuration defaults to `%APPDATA%/xtpkg/config.json` on Windows and
`$XDG_CONFIG_HOME/xtpkg/config.json` or `~/.config/xtpkg/config.json` on Unix.
`XTPKG_CONFIG_HOME` overrides the parent config directory.

## Publishing and manual approval

1. Put `xtpkg.toml`, the entrypoint, a `LICENSE`, `LICENSE.md`, or `LICENSE.txt`,
   and every package file under Git version control. Set package description,
   license, and a credential-free HTTPS repository URL.
2. Commit the version being submitted. Use `.gitignore` for generated/private
   files, and keep the repository working tree clean, including untracked files.
3. Run `xtpkg publish --dry-run`. This validates the committed Git tree, metadata,
   identity, dependency ranges, safe paths, entrypoint, and supported text files.
   It writes no project/cache files and creates no submission. Temporary bare
   Git storage outside the project is removed after validation.
4. Run `xtpkg publish --output submission.json`. The output must be a new, safe
   relative filename whose parent already exists. Existing files are never
   overwritten. The output is a package metadata record containing one version.
5. Push the referenced commit to the declared repository yourself. Submit a PR
   to the registry that merges this new version into its package metadata file
   and adds/updates the discovery index. **Preserve every existing version.**
6. Registry maintainers review the code and metadata, validate the registry,
   and approve the submission by merging the PR. Installation needs no GitHub
   authentication for public repositories. There is no public write API.

Ignore or move generated submissions before a subsequent clean-tree publish
check. Publishing checks local committed contents; it does not verify that a
commit has already been pushed or that the declared remote serves that commit.

## Resolution, lockfiles, and migration

Version precedence follows [SemVer 2.0](https://semver.org/spec/v2.0.0.html),
including numeric prerelease identifiers and ignored build metadata. Supported
ranges: exact, `^`, `~`, `>=`, `<=`, `>`, `<`, whitespace intersections such as
`>=1.0.0 <2.0.0`, `1.2.x`/`1.2.*`, and `*`. Prereleases are excluded unless a
range explicitly includes a prerelease with the same major/minor/patch tuple.
OR ranges, hyphen ranges, and abbreviated versions are currently unsupported.

The resolver deterministically tries highest compatible versions, with bounded
backtracking and preference for compatible existing locks. One version per name
is installed; incompatible graphs fail with requirement chains. Cycles fail.
Limits: 256 packages, 256 declarations per manifest, 128 graph depth, and 10,000
resolution attempts. An unscoped package cannot also be another package's scope.

`xtpkg.lock` remains TOML. Format 2 extends the previous package map with roots,
name, version, source, exact revision, SHA-256 integrity, entrypoint, requirements,
and resolved dependency versions. Dependency maps are canonical JSON strings
inside TOML scalars, avoiding unsupported runtime TOML nesting behavior.
Unchanged roots reuse the exact graph, even if registry metadata changes.

Legacy format 1 locks are read and migrated by a normal `install`; they cannot
meet `--locked`/`--frozen` because they lack immutable artifact identities.
An old `packages/` tree is adopted only when all top-level directories match
the legacy lock. An unmarked unrelated tree is refused.

Local paths are immutable snapshots in a lock: normal installs reproduce the
snapshot, and `update` refreshes it. Moving a project invalidates locked relative
path roots if their absolute source location changes. `--offline` cannot create
a fresh local snapshot; it needs an existing lock/cache. Frozen mode does not
need a registry configuration at all.

## Runtime imports

LuauXTX currently supports relative/absolute file imports and built-in modules;
it does not resolve bare registry names. XTPKG implements its side without
changing runtime code in another repository:

```luau
-- src/main.luau in the application
local packages = require("../packages/.xtpkg-imports")
local json = packages.require("example/json")

-- Or use the generated relative wrapper directly:
local sameJson = require("../packages/example/json")
```

Every package has a sibling `.luau` wrapper that imports its declared entrypoint.
Its original files live under `packages/<name>/`. Packages can use ordinary
relative imports to sibling dependency wrappers: an `example/json` package with
an entry at `init.luau` imports `example/core` via `require("../core")`.
Adjust relative paths for deeper entrypoints. Existing internal relative imports
are preserved. No bare `require("example/json")` support is claimed.

`packages/.xtpkg-imports.json` is the runtime integration contract: each name
maps to a relative wrapper path, original entry, resolved version, and revision.
The generated `.xtpkg-imports.luau` adapter captures LuauXTX's directory-bound
`require` before exposing its named lookup function. Package code should likewise
capture `local moduleRequire = require` at module scope when requiring modules
inside functions, matching this runtime's current loader behavior.

## Integrity, safety, cache, and transactions

Artifacts are UTF-8 text Git trees or local snapshots, up to 2,048 files, 1 MiB
per file, and 16 MiB of contents. Portable paths use ASCII letters, digits,
spaces, `.`, `_`, `-`, `+`, `@`, parentheses, and `/` separators. Unicode filename
collisions and Windows short-name aliases are avoided by rejecting other
characters; file contents may contain Unicode. Case collisions and
file/directory collisions are rejected, and Git symlinks/submodules are refused.
No archive extraction or checkout occurs. Git blobs are checked against their
original Git object IDs after transport through the runtime's text process API.
Native libraries, executables, archives, credential files, `.env` files, and
tracked build/dependency output directories are rejected. Pure Luau is the
supported package type; native capabilities are reserved and rejected.

Integrity is SHA-256 of the canonical JSON object mapping every package-relative
filename to its complete UTF-8 text, with keys sorted, standard short JSON
escapes, and unescaped UTF-8 characters. This excludes generated wrappers and
includes the original manifest. Publish emits this checksum; installation
compares it when provided and always records a verified snapshot checksum.
An immutable Git object identity plus checksums detects changed bytes, but does
not establish author identity or code trust. This registry has no signatures.

Cache defaults: `%LOCALAPPDATA%/xtpkg/cache`, `$XDG_CACHE_HOME/xtpkg`, or
`~/.cache/xtpkg`. Override the exact root with `XTPKG_CACHE_DIR`. Metadata keys
include registry location; artifact keys include source, name, version, and
revision. Every cache read verifies its envelope checksum, and package reads
also check contents and manifest identity. Corruption fails; run `cache clean`
and reinstall online to repair it. Cleanup checks ownership and deletes only
known managed files. It never recursively deletes a configured cache root.

Install/add/remove/update acquire a project operation guard, build a complete
staging tree, and rename backups and replacements with rollback on ordinary
failures. Project manifests and locks are replaced only after downloads and
validation succeed. `packages/` is a managed directory: do not store unrelated
files inside it. Unrelated project files outside it are never replaced.

## Validation and current limits

```text
python -u tests/run.py
python -u tests/run.py --runtime /absolute/path/to/luauxtx
```

The runner creates temporary Git packages and a registry, exercises the real
LuauXTX CLI and imports, and uses no public services. Unit suites cover parsing,
SemVer, names, paths, metadata, resolver backtracking/conflicts/cycles, and cache
snapshot validation. The HTTPS client is tested with mocked responses, including
oversized and malformed bodies and a failing transport. Integration coverage includes exact commits, lock reuse,
targeted/all updates, offline resolution, frozen reproduction, corrupted/missing
artifacts, failed fetches, injected transaction rollback, removal, path imports,
publishing, registry immutability validation, Git symlinks, filesystem junctions,
legacy migration, unmanaged directory preservation, configuration, and cache cleanup.

Known limits and follow-up work:

- No native dependencies, install hooks, arbitrary archive sources, signatures,
  credential manager, private registry auth, or automatic GitHub PR creation.
- The runtime HTTP client buffers responses before XTPKG can enforce its 2 MiB
  parsing limit; it exposes no streaming body limit or request timeout. Git fetch
  size and execution time are also not bounded by the current process API.
- The runtime lacks `lstat`, safe directory handles, binary process output, and
  a filesystem transaction primitive. OS link checks reject existing escapes,
  but cannot eliminate malicious concurrent filesystem changes (TOCTOU).
- Rollback handles reported errors, not power loss or a process killed during
  rename. Interrupted `.xtpkg-stage-*` backups and `.xtpkg-operation` guards need
  manual inspection/recovery before reuse. Cache clean refuses unknown temporary
  directories left by interrupted fetches.
- The automated suite runs on the current Windows environment; Unix branches
  need platform CI. Public HTTPS retrieval and GitHub hosting need an integration
  smoke test once a real registry is configured.
- LuauXTX's current loader caches paths without canonicalizing `..`/`.` segments.
  Different import spellings may instantiate a module more than once. Use a
  consistent import adapter/path convention until the runtime canonicalizes keys.
- Next runtime improvements: bounded HTTP/process APIs, non-following filesystem
  metadata/handles, and a native consumer for `.xtpkg-imports.json`. Next registry
  improvements: CI immutability checks, code review policy, and signed provenance.
