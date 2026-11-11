local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("../package/Manifest")
local Source = require("../package/Source")
local Json = require("../package/Json")
local Util = require("../package/Util")
local Metadata = require("../registry/Metadata")
return { run = function(args)
    if args._[2] then error("Usage: xtpkg publish [--dry-run] [--output file]", 0) end
    local cwd = path.normalize(process.cwd()); local manifest = Manifest.load(cwd); local p = manifest.package
    for _, field in ipairs({ "description", "license", "repository" }) do if not p[field] then error("Publishing requires package." .. field, 0) end end
    Metadata.dependencies(manifest.dependencies)
    local root = path.normalize(Util.git({ "rev-parse", "--show-toplevel" }, cwd):match("^([^\r\n]+)"))
    if root:lower() ~= cwd:lower() then error("Publish from the Git repository root containing xtpkg.toml", 0) end
    if Util.git({ "status", "--porcelain", "--untracked-files=normal" }, cwd) ~= "" then error("Publishing requires a clean Git working tree, including untracked files. Commit package files and ignore generated/private files first.", 0) end
    local revision = Util.git({ "rev-parse", "HEAD^{commit}" }, cwd):match("^%x+")
    local temporaryBase = process.getenv("TEMP") or process.getenv("TMPDIR") or "/tmp"
    local snapshot = Source.gitSnapshot(cwd, revision, temporaryBase, true)
    local committed = Source.validate(snapshot, { name = p.name, version = p.version, entry = p.entry, dependencies = manifest.dependencies })
    if not snapshot.files["LICENSE"] and not snapshot.files["LICENSE.md"] and not snapshot.files["LICENSE.txt"] then error("Publishing requires a tracked LICENSE, LICENSE.md, or LICENSE.txt file", 0) end
    if committed.package.repository ~= p.repository then error("Committed repository metadata differs from the working manifest", 0) end
    local submission = { name = p.name, description = p.description, repository = p.repository, license = p.license, versions = { [p.version] = { source = { type = "git", url = p.repository, revision = revision }, entry = p.entry, integrity = snapshot.integrity, dependencies = manifest.dependencies } } }
    Metadata.validate(submission, p.name)
    args.log("Validated " .. p.name .. "@" .. p.version .. " at " .. revision)
    if args["dry-run"] then args.log("Dry run complete; no submission or project files were written."); return end
    local output = args.output or "xtpkg-submission.json"
    if not Util.relative(output) then error("--output must be a safe relative path inside the project", 0) end
    Source.allowed(output)
    local destination = path.join(cwd, output); Util.noLinks(destination)
    if fs.exists(destination) then error("Submission output already exists: " .. output .. ". Choose a new --output path.", 0) end
    if not fs.exists(path.dirname(destination)) then error("Submission output parent directory does not exist", 0) end
    local temporary = destination .. "." .. Util.id()
    fs.writeSync(temporary, Json.encode(submission) .. "\n"); fs.rename(temporary, destination):await()
    args.log("Wrote " .. output .. "\nPush commit " .. revision .. " to " .. p.repository .. ".\nOpen a pull request against your registry repository:\n  Merge this version into packages/" .. p.name .. ".json; preserve every existing immutable version.\n  Add/update index.json packages[" .. Json.encode(p.name) .. "] with its metadata path and description.\nRegistry maintainers review and merge the PR. This command does not upload or publish anything.")
end }
