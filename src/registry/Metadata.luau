local Util = require("../package/Util")
local SemVer = require("../package/SemVer")
local Manifest = require("../package/Manifest")
local path = require("system/path")
local Json = require("../package/Json")
local Metadata = {}
function Metadata.dependencies(deps)
    if not Json.object(deps) then error("Metadata dependencies must be an object", 0) end
    local n = 0
    for name, spec in pairs(deps) do
        n += 1; if n > 256 then error("Too many metadata dependencies", 0) end
        if not Util.name(name) then error("Invalid metadata dependency identity", 0) end
        Manifest.specification(spec, true)
    end
    return deps
end
function Metadata.validate(data, name, allowLocal)
    if not Json.object(data) or data.name ~= name or not Util.name(name) then error("Registry package identity mismatch: " .. tostring(name), 0) end
    for _, field in ipairs({ "description", "repository" }) do
        if type(data[field]) ~= "string" or #data[field] > 4096 or data[field]:find("%c") then error("Invalid package metadata: " .. field, 0) end
    end
    if not Util.url(data.repository) then error("Invalid metadata repository URL", 0) end
    if not Json.object(data.versions) then error("Package metadata is missing versions", 0) end
    local n = 0
    for version, record in pairs(data.versions) do
        n += 1; if n > 1000 then error("Too many package versions", 0) end
        SemVer.parse(version)
        if not Json.object(record) or not Json.object(record.source) then error("Invalid source metadata for " .. name .. "@" .. version, 0) end
        local source = record.source
        local safeURL = Util.url(source.url) or (allowLocal and type(source.url) == "string" and path.isAbsolute(source.url) and not source.url:find("%c"))
        if source.type ~= "git" or not safeURL or not Util.revision(source.revision) then error("Registry versions require type=git, an HTTPS URL, and an immutable 40-character commit revision: " .. name .. "@" .. version .. ". Local Git fixtures need a local registry and --allow-local-sources.", 0) end
        if record.integrity ~= nil and not Util.checksum(record.integrity) then error("Invalid SHA-256 integrity", 0) end
        if record.entry ~= nil and (not Util.relative(record.entry) or not record.entry:match("%.luau?$")) then error("Invalid metadata entrypoint", 0) end
        if record.native ~= nil or record.capabilities ~= nil then error("Native capabilities are not supported by this XTPKG version", 0) end
        if record.dependencies == nil then record.dependencies = {} end
        record.dependencies = Metadata.dependencies(record.dependencies)
    end
    if n == 0 then error("Package has no published versions: " .. name, 0) end
    return data
end
function Metadata.index(data)
    if not Json.object(data) or data.registry_version ~= 1 or not Json.object(data.packages) then error("Invalid registry index (expected registry_version=1 and packages object)", 0) end
    local n, seen = 0, {}
    for name, record in pairs(data.packages) do
        n += 1; if n > 10000 then error("Registry index exceeds package limit", 0) end
        if not Util.name(name) or type(record) ~= "table" or type(record.path) ~= "string" or not Util.relative(record.path) or not record.path:match("%.json$") then error("Unsafe or malformed registry index entry", 0) end
        if seen[record.path:lower()] then error("Duplicate registry metadata path", 0) end
        seen[record.path:lower()] = true
        if record.description ~= nil and (type(record.description) ~= "string" or #record.description > 4096 or record.description:find("%c")) then error("Invalid index description", 0) end
    end
    return data
end
return Metadata
