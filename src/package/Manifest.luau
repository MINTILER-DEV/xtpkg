local toml = require("serde/toml")
local fs = require("system/fs")
local path = require("system/path")

local Manifest = {}

function Manifest.exists(directory)
    local manifestPath = path.join(directory, "xtpkg.toml")
    return fs.exists(manifestPath)
end

function Manifest.create(directory, options)
    options = options or {}

    local manifestPath = path.join(directory, "xtpkg.toml")
    if fs.exists(manifestPath) and not options.force then
        error("xtpkg.toml already exists")
    end

    local manifest = {
        package = {
            name = options.name or path.basename(directory),
            version = "0.1.0",
            entry = "src/main.luau",
        },
        dependencies = {},
        scripts = {
            start = "luauxtx src/main.luau",
        },
    }

    local tomlString = toml.encode(manifest)
    fs.write(manifestPath, tomlString)
end



return Manifest
