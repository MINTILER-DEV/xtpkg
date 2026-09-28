local fs = require("system/fs")
local path = require("system/path")
local toml = require("serde/toml")

local Lockfile = {}

local function filename(directory) return path.join(directory, "xtpkg.lock") end
local function quote(value) return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end

function Lockfile.load(directory)
    if not fs.exists(filename(directory)) then return { lock_version = 1, packages = {} } end
    local ok, lock = pcall(toml.decode, fs.readSync(filename(directory)))
    if not ok or type(lock) ~= "table" or lock.lock_version ~= 1 then
        error("xtpkg.lock is malformed or uses an unsupported format")
    end
    lock.packages = lock.packages or {}
    if type(lock.packages) ~= "table" then error("xtpkg.lock is malformed or uses an unsupported format") end
    return lock
end

function Lockfile.save(directory, lock)
    if type(lock) ~= "table" or type(lock.packages) ~= "table" then error("invalid lockfile") end
    local names = {}
    for name, package in pairs(lock.packages) do
        if type(name) ~= "string" or not name:match("^[a-z0-9][a-z0-9%-_]*$") or type(package) ~= "table" or type(package.version) ~= "string" or type(package.source) ~= "string" then
            error("invalid lockfile package entry")
        end
        table.insert(names, name)
    end
    table.sort(names)
    local lines = { "lock_version = 1" }
    for _, name in ipairs(names) do
        local package = lock.packages[name]
        table.insert(lines, "")
        table.insert(lines, "[packages." .. name .. "]")
        table.insert(lines, "source = " .. quote(package.source))
        table.insert(lines, "version = " .. quote(package.version))
    end
    fs.writeSync(filename(directory), table.concat(lines, "\n") .. "\n")
end

return Lockfile
