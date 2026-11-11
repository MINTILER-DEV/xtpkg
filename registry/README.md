# Registry template

This is an empty registry template, not a configured public registry. Copy it
into a dedicated GitHub repository, enable branch protection and required PR
review, and configure XTPKG with its raw HTTPS base URL or a local directory.

Keep `index.json` as a discovery map. Store package records under
`packages/<scope>/<name>.json` (or `packages/<name>.json` for unscoped packages).
Use `xtpkg publish` in a package repository to generate an immutable version
record. Merge the new version into the existing record, preserving all old
versions, and update the index's metadata path/description.

New packages and versions require a pull request. Maintainers review identity,
repository ownership, license, source code, dependency declarations, entrypoint,
commit availability, and checksum. Merge approval makes metadata visible to
clients. A Git commit/checksum identifies bytes; it does not certify their safety.
Do not approve native capabilities or mutable tag-only versions.

Validate a candidate registry with:

```text
luauxtx tools/validate-registry.luau path/to/candidate [path/to/previous]
```

Run the validator from the XTPKG checkout, with LuauXTX and Git installed. The
optional previous snapshot enforces that existing packages and versions remain
present and unchanged. CI should provide the base branch registry as `previous`
and require this check before merging. Do not use a PR's own modified validator
as a trusted approval gate. The validator is read-only and does not fetch code.

Local test registries can use absolute paths to Git fixture repositories with
`--allow-local-sources`; production metadata must use public HTTPS Git URLs.
No write API or GitHub authentication is required by XTPKG for public installs.
