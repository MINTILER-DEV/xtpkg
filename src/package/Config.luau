local fs = require("system/fs")
local path = require("system/path")
local Json = require("./Json")
local Util = require("./Util")
local Config = {}
function Config.home()
    local base = process.getenv("XTPKG_CONFIG_HOME") or process.getenv("APPDATA") or process.getenv("XDG_CONFIG_HOME")
    return base and path.join(base, "xtpkg") or path.join(assert(process.getenv("HOME"), "Set XTPKG_CONFIG_HOME"), ".config", "xtpkg")
end
function Config.cache()
    local explicit = process.getenv("XTPKG_CACHE_DIR")
    if explicit then return Util.absolute(process.cwd(), explicit) end
    local windows, xdg = process.getenv("LOCALAPPDATA"), process.getenv("XDG_CACHE_HOME")
    if windows then return path.join(windows, "xtpkg", "cache") end
    if xdg then return path.join(xdg, "xtpkg") end
    return path.join(assert(process.getenv("HOME"), "Set XTPKG_CACHE_DIR"), ".cache", "xtpkg")
end
function Config.load()
    local filename = path.join(Config.home(), "config.json"); Util.noLinks(filename)
    if not fs.exists(filename) then return {} end
    if fs.stat(filename):await().size > 65536 then error("Configuration exceeds size limit", 0) end
    local t = Json.decode(fs.readSync(filename), 65536)
    if not Json.object(t) then error("Invalid configuration", 0) end
    return t
end
function Config.validateRegistry(value)
    if type(value) ~= "string" or value == "" or value:find("%c") then error("Invalid registry location", 0) end
    if value:match("^https?://") then
        if not Util.url(value) then error("Registry must be credential-free HTTPS or a local directory", 0) end
    elseif value:find("://", 1, true) then error("Unsupported registry transport", 0) end
    return value:gsub("/$", "")
end
function Config.registry()
    local value = process.getenv("XTPKG_REGISTRY") or Config.load().registry
    if not value then error("No registry configured. Run xtpkg config set registry <HTTPS base URL or local directory>, or set XTPKG_REGISTRY.", 0) end
    return Config.validateRegistry(value)
end
function Config.set(key, value)
    if key ~= "registry" then error("Unknown config key: " .. tostring(key), 0) end
    value = Config.validateRegistry(value)
    if not value:match("^https://") then value = Util.absolute(process.cwd(), value) end
    local t = Config.load(); t[key] = value
    Util.noLinks(Config.home()); Util.mkdir(Config.home())
    local filename = path.join(Config.home(), "config.json"); local temp = filename .. "." .. Util.id()
    fs.writeSync(temp, Json.encode(t) .. "\n"); fs.rename(temp, filename):await()
end
return Config
