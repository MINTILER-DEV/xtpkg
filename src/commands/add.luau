local path = require("system/path")
local Manifest = require("../package/Manifest")
local Resolver = require("../package/Resolver")

local add = {}

local function localPath(directory, specification)
    local value = specification:sub(1, 5) == "path:" and specification:sub(6) or specification
    return path.isAbsolute(value) and path.normalize(value) or path.join(directory, value)
end

function add.run(args)
    local requested = args._[2]
    if not requested then error("Usage: xtpkg add <local-path> or xtpkg add <name>@path:<local-path>") end
    local cwd = process.cwd()
    local name, specification = requested:match("^([a-z0-9][a-z0-9%-_]*)@(.+)$")
    specification = specification or requested

    if not Resolver.isPathSpec(specification) then
        error("Cannot add " .. requested .. ": no package registry is configured. Local paths are supported.")
    end
    local dependency = Manifest.load(localPath(cwd, specification))
    name = name or dependency.package.name
    if name ~= dependency.package.name then error("Dependency name " .. name .. " does not match local package name " .. dependency.package.name) end

    local manifest = Manifest.load(cwd)
    Manifest.addDependency(manifest, name, specification:sub(1, 5) == "path:" and specification or "path:" .. specification)
    Manifest.save(cwd, manifest)
    print("Added " .. name .. " (run xtpkg install to resolve it)")
end

return add
