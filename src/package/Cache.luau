local fs = require("system/fs")
local path = require("system/path")
local Config = require("./Config")
local Json = require("./Json")
local Util = require("./Util")
local Cache = {}
local marker = "xtpkg-cache-v1\n"
function Cache.root(create)
    local root = Config.cache(); Util.noLinks(root)
    local m = path.join(root, ".xtpkg-cache"); Util.noLinks(m)
    if fs.exists(m) then
        if fs.readSync(m) ~= marker then error("Invalid XTPKG cache ownership marker", 0) end
    elseif create then
        if fs.exists(root) and #fs.readDir(root):await() ~= 0 then error("Refusing to adopt a non-empty unmanaged cache directory: " .. root, 0) end
        Util.mkdir(root); fs.writeSync(m, marker)
    elseif fs.exists(root) and #fs.readDir(root):await() ~= 0 then error("Unmanaged cache directory: " .. root, 0) end
    return root
end
function Cache.read(kind, key, limit)
    assert(kind == "metadata" or kind == "packages", "Invalid cache kind")
    local filename = path.join(Cache.root(false), kind, Util.sha(key) .. ".json")
    Util.noLinks(filename)
    if not fs.exists(filename) then return nil end
    if fs.stat(filename):await().size > (limit or 2 * 1024 * 1024) then error("Cached data exceeds size limit", 0) end
    local envelope = Json.decode(fs.readSync(filename), limit)
    if not Json.object(envelope) or envelope.key ~= key or not Json.object(envelope.data) or envelope.checksum ~= Util.sha(Json.encode(envelope.data)) then error("Corrupted " .. kind .. " cache; run xtpkg cache clean", 0) end
    return envelope.data
end
function Cache.write(kind, key, data)
    assert(kind == "metadata" or kind == "packages", "Invalid cache kind")
    local root = Cache.root(true); local dir = path.join(root, kind); Util.noLinks(dir); Util.mkdir(dir)
    local filename = path.join(dir, Util.sha(key) .. ".json"); Util.noLinks(filename)
    local temporary = filename .. "." .. Util.id()
    fs.writeSync(temporary, Json.encode({ key = key, checksum = Util.sha(Json.encode(data)), data = data }))
    local ok, err = pcall(function() fs.rename(temporary, filename):await() end)
    if not ok then Util.remove(temporary); error(err, 0) end
end
function Cache.packageKey(p) return Json.encode({ name = p.name, version = p.version, source = p.source, revision = p.revision }) end
function Cache.entries()
    local root, entries = Cache.root(false), {}
    for _, kind in ipairs({ "metadata", "packages" }) do
        local dir = path.join(root, kind); Util.noLinks(dir)
        if fs.exists(dir) then
            for _, file in ipairs(fs.readDir(dir):await()) do
                if not file:match("^[0-9a-f]+%.json$") or #file ~= 69 then error("Unexpected file in managed cache: " .. file, 0) end
                local location = path.join(dir, file); Util.noLinks(location)
                if not fs.stat(location):await().isFile then error("Unexpected directory in cache", 0) end
                table.insert(entries, { kind = kind, file = location })
            end
        end
    end
    table.sort(entries, function(a, b) return a.file < b.file end)
    return entries
end
function Cache.verify(validator, metadataValidator)
    local entries = Cache.entries()
    for _, e in ipairs(entries) do
        if fs.stat(e.file):await().size > 64 * 1024 * 1024 then error("Oversized cache artifact", 0) end
        local envelope = Json.decode(fs.readSync(e.file), 64 * 1024 * 1024)
        if type(envelope) ~= "table" or type(envelope.key) ~= "string" or path.basename(e.file) ~= Util.sha(envelope.key) .. ".json" then error("Corrupted cache identity", 0) end
        local data = Cache.read(e.kind, envelope.key, 64 * 1024 * 1024)
        if e.kind == "packages" and validator then validator(data) end
        if e.kind == "metadata" and metadataValidator then metadataValidator(data, envelope.key) end
    end
    return #entries
end
function Cache.clean()
    -- Validate all managed children before deleting any. Never recursively
    -- delete a caller-provided cache root or an unknown directory.
    local root = Cache.root(false); local entries = Cache.entries()
    if fs.exists(root) then
        for _, child in ipairs(fs.readDir(root):await()) do
            if child ~= ".xtpkg-cache" and child ~= "metadata" and child ~= "packages" then error("Unexpected child in managed cache; refusing cleanup: " .. child, 0) end
        end
    end
    for _, e in ipairs(entries) do fs.remove(e.file):await() end
    return #entries
end
return Cache
