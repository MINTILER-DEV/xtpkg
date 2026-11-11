local fs = require("system/fs")
local path = require("system/path")
local http = require("net/http")
local Config = require("../package/Config")
local Cache = require("../package/Cache")
local Json = require("../package/Json")
local Util = require("../package/Util")
local Metadata = require("./Metadata")
local Client = {}
function Client.new(options)
    options = options or {}
    local base = Config.validateRegistry(options.registry or Config.registry())
    if not base:match("^https://") then base = Util.absolute(process.cwd(), base) end
    local self = { base = base, offline = options.offline or options.frozen, memory = {}, allowLocal = options["allow-local-sources"] and not base:match("^https://") }
    function self:read(relative, validator)
        if self.memory[relative] then return self.memory[relative] end
        local key = self.base .. "/" .. relative
        local data
        if self.offline then
            data = Cache.read("metadata", key)
            if not data then error("Offline registry metadata is missing: " .. relative .. ". Run an online install/search first.", 0) end
        else
            local body
            if self.base:match("^https://") then
                local ok, response = pcall(function() return http.fetch(key):await() end)
                if not ok or not response.ok then error("Could not retrieve registry metadata: " .. relative .. ". Check registry configuration and connectivity.", 0) end
                body = response.body
            else
                local filename = path.join(self.base, relative); Util.noLinks(filename)
                if not fs.exists(filename) then error("Registry metadata file is missing: " .. relative, 0) end
                if fs.stat(filename):await().size > 2 * 1024 * 1024 then error("Registry metadata exceeds 2 MiB limit", 0) end
                body = fs.readSync(filename)
            end
            data = Json.decode(body)
        end
        data = validator(data)
        if not self.offline and relative ~= "index.json" then
            local previous = Cache.read("metadata", key)
            if previous then
                previous = validator(previous)
                for version, record in pairs(previous.versions) do
                    if not data.versions[version] or Json.encode(record) ~= Json.encode(data.versions[version]) then error("Registry changed or removed an immutable version: " .. data.name .. "@" .. version .. ". Contact the registry maintainer.", 0) end
                end
            end
        end
        if not self.offline then Cache.write("metadata", key, data) end
        self.memory[relative] = data
        return data
    end
    function self:index() return self:read("index.json", Metadata.index) end
    function self:package(name)
        if not Util.name(name) then error("Invalid package name: " .. tostring(name), 0) end
        local index = self:index(); local record = index.packages[name]
        if not record then
            local suggestions = {}
            local needle = name:match("([^/]+)$")
            for _, candidate in ipairs(Util.keys(index.packages)) do
                local leaf = candidate:match("([^/]+)$")
                -- Only suggest an exact leaf or a single-character typo.
                local function distance(a, b)
                    local row = {}; for j = 0, #b do row[j] = j end
                    for i = 1, #a do local prev = row[0]; row[0] = i; for j = 1, #b do local old = row[j]; row[j] = math.min(row[j] + 1, row[j - 1] + 1, prev + (a:sub(i, i) == b:sub(j, j) and 0 or 1)); prev = old end end
                    return row[#b]
                end
                if #needle >= 3 and distance(needle, leaf) <= 1 then table.insert(suggestions, candidate) end
            end
            error('Package "' .. name .. '" was not found.' .. (#suggestions > 0 and " Did you mean: " .. table.concat(suggestions, ", ") .. "?" or "") .. " Run xtpkg search <term>.", 0)
        end
        return self:read(record.path, function(data) return Metadata.validate(data, name, self.allowLocal) end)
    end
    return self
end
return Client
