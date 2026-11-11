local fs = require("system/fs")
local path = require("system/path")
local Json = require("../src/package/Json")
local Util = require("../src/package/Util")
local Metadata = require("../src/registry/Metadata")
local args = { ... }
local function read(root, relative)
    local filename = path.join(root, relative); Util.noLinks(filename)
    if fs.stat(filename):await().size > 2 * 1024 * 1024 then error("Oversized registry metadata", 0) end
    return Json.decode(fs.readSync(filename))
end
local function validate(root)
    local index = Metadata.index(read(root, "index.json")); local packages = {}
    for _, name in ipairs(Util.keys(index.packages)) do packages[name] = Metadata.validate(read(root, index.packages[name].path), name) end
    return packages
end
local ok, err = pcall(function()
    if not args[1] or args[3] then error("Usage: luauxtx tools/validate-registry.luau <candidate> [previous]", 0) end
    local candidate = validate(args[1]); local count = 0
    if args[2] then
        local previous = validate(args[2])
        for name, p in pairs(previous) do
            if not candidate[name] then error("Existing package was removed: " .. name, 0) end
            for version, record in pairs(p.versions) do
                if not candidate[name].versions[version] or Json.encode(record) ~= Json.encode(candidate[name].versions[version]) then error("Immutable version was removed or changed: " .. name .. "@" .. version, 0) end
            end
        end
    end
    for _ in pairs(candidate) do count += 1 end
    print("Validated " .. count .. " registry packages")
end)
if not ok then print("error: " .. tostring(err):gsub("\nstack traceback:.*", "")); process.exit(1) end
