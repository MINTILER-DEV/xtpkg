local toml = require("serde/toml")
local fs = require("system/fs")
local path = require("system/path")

local Manifest = {}

local function manifestPath(directory)
    return path.join(directory, "xtpkg.toml")
end

local function validName(name)
    return type(name) == "string" and name:match("^[a-z0-9][a-z0-9%-_]*$") ~= nil
end

local function sortedKeys(values)
    local keys = {}
    for key in pairs(values) do table.insert(keys, key) end
    table.sort(keys)
    return keys
end

function Manifest.exists(directory)
    return fs.exists(manifestPath(directory))
end

function Manifest.validate(manifest)
    if type(manifest) ~= "table" then error("xtpkg.toml must contain a table") end
    if type(manifest.package) ~= "table" then error("xtpkg.toml is missing [package]") end
    if not validName(manifest.package.name) then error("package.name must use lowercase letters, numbers, hyphens, or underscores") end
    if type(manifest.package.version) ~= "string" or not manifest.package.version:match("^%d+%.%d+%.%d+[%w%.%-]*$") then
        error("package.version must be a semantic version")
    end
    if type(manifest.package.entry) ~= "string" or manifest.package.entry == "" then error("package.entry must be a non-empty string") end

    for _, section in ipairs({ "dependencies", "scripts" }) do
        manifest[section] = manifest[section] or {}
        if type(manifest[section]) ~= "table" then error(section .. " must be a table") end
        for key, value in pairs(manifest[section]) do
            if type(key) ~= "string" or type(value) ~= "string" or value == "" then
                error(section .. " entries must have non-empty string keys and values")
            end
            if section == "dependencies" and not validName(key) then error("invalid dependency name: " .. key) end
        end
    end
    return manifest
end

function Manifest.load(directory)
    local filename = manifestPath(directory)
    if not fs.exists(filename) then error("No xtpkg.toml found in " .. directory) end
    local ok, manifest = pcall(toml.decode, fs.readSync(filename))
    if not ok then error("Could not parse xtpkg.toml: " .. tostring(manifest)) end
    return Manifest.validate(manifest)
end

function Manifest.save(directory, manifest)
    Manifest.validate(manifest)
    local ordered = { package = manifest.package, dependencies = {}, scripts = {} }
    for _, key in ipairs(sortedKeys(manifest.dependencies)) do ordered.dependencies[key] = manifest.dependencies[key] end
    for _, key in ipairs(sortedKeys(manifest.scripts)) do ordered.scripts[key] = manifest.scripts[key] end
    fs.writeSync(manifestPath(directory), toml.encode(ordered) .. "\n")
end

function Manifest.create(directory, options)
    options = options or {}
    if Manifest.exists(directory) and not options.force then error("xtpkg.toml already exists (use --force to overwrite)") end
    local manifest = {
        package = { name = options.name or path.basename(directory), version = "0.1.0", entry = "src/main.luau" },
        dependencies = {}, scripts = { start = "luauxtx src/main.luau" },
    }
    Manifest.save(directory, manifest)
    return manifest
end

function Manifest.addDependency(manifest, name, specification)
    if not validName(name) then error("invalid dependency name: " .. tostring(name)) end
    if type(specification) ~= "string" or specification == "" then error("dependency specification must be a non-empty string") end
    manifest.dependencies = manifest.dependencies or {}
    manifest.dependencies[name] = specification
end

function Manifest.removeDependency(manifest, name)
    if not manifest.dependencies or not manifest.dependencies[name] then error("Dependency not found: " .. name) end
    manifest.dependencies[name] = nil
end

return Manifest
