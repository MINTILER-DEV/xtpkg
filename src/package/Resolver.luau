local path = require("system/path")
local Manifest = require("./Manifest")

local Resolver = {}

local function isPathSpec(specification)
    return specification:sub(1, 5) == "path:" or specification:sub(1, 2) == "./" or specification:sub(1, 3) == "../" or path.isAbsolute(specification)
end

local function sourcePath(directory, specification)
    local value = specification:sub(1, 5) == "path:" and specification:sub(6) or specification
    if value == "" then error("path dependency has an empty path") end
    return path.isAbsolute(value) and path.normalize(value) or path.join(directory, value)
end

function Resolver.resolve(directory, manifest)
    local resolved, resolving = {}, {}
    local function visit(name, specification, parent)
        if not isPathSpec(specification) then
            error("Cannot resolve " .. name .. ": no registry is configured. Use a local path dependency such as path:../" .. name)
        end
        local location = sourcePath(parent, specification)
        if resolving[location] then error("Circular local dependency detected at " .. name) end
        local dependency = Manifest.load(location)
        if dependency.package.name ~= name then
            error("Dependency name " .. name .. " does not match local package name " .. dependency.package.name)
        end
        local current = resolved[name]
        if current then
            if current.source ~= "path:" .. location or current.version ~= dependency.package.version then error("Conflicting dependency resolution for " .. name) end
            return
        end
        resolving[location] = true
        resolved[name] = { version = dependency.package.version, source = "path:" .. location }
        for childName, childSpec in pairs(dependency.dependencies) do visit(childName, childSpec, location) end
        resolving[location] = nil
    end
    for name, specification in pairs(manifest.dependencies) do visit(name, specification, directory) end
    return { lock_version = 1, packages = resolved }
end

function Resolver.isPathSpec(specification) return isPathSpec(specification) end

return Resolver
