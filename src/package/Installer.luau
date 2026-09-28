local fs = require("system/fs")
local path = require("system/path")

local Installer = {}

local function packagePath(directory, name)
    if type(name) ~= "string" or not name:match("^[a-z0-9][a-z0-9%-_]*$") then error("unsafe package name in lockfile") end
    return path.join(directory, "packages", name)
end

local function sourcePath(package)
    if type(package.source) ~= "string" or package.source:sub(1, 5) ~= "path:" then
        error("Unsupported package source: " .. tostring(package.source))
    end
    local source = package.source:sub(6)
    if source == "" or not fs.exists(source) then error("Local package source does not exist: " .. source) end
    return source
end

function Installer.install(directory, previousLock, lock)
    local packagesDirectory = path.join(directory, "packages")
    if not fs.exists(packagesDirectory) then fs.mkdir(packagesDirectory, true):await() end

    for name in pairs(previousLock.packages) do
        if not lock.packages[name] then
            local destination = packagePath(directory, name)
            if fs.exists(destination) then fs.remove(destination, true):await() end
        end
    end

    local names = {}
    for name in pairs(lock.packages) do table.insert(names, name) end
    table.sort(names)
    for _, name in ipairs(names) do
        local destination = packagePath(directory, name)
        local source = sourcePath(lock.packages[name])
        if path.normalize(source) == path.normalize(destination) then error("Refusing to install a package onto its own source: " .. name) end
        if fs.exists(destination) then fs.remove(destination, true):await() end
        fs.copy(source, destination, true):await()
    end
end

return Installer
