local fs = require("system/fs")
local path = require("system/path")
local legacyToml = require("serde/toml")
local Json = require("./Json")
local Util = require("./Util")
local SemVer = require("./SemVer")
local Manifest = require("./Manifest")
local Lockfile = {}
function Lockfile.empty() return { lock_version = 2, roots = {}, packages = {} } end
function Lockfile.validate(lock)
    if not Json.object(lock) or lock.lock_version ~= 2 or not Json.object(lock.roots) or not Json.object(lock.packages) then error("Malformed or unsupported xtpkg.lock; run xtpkg install to regenerate it", 0) end
    local count = 0
    for name, spec in pairs(lock.roots) do
        if not Util.name(name) then error("Unsafe lockfile root identity", 0) end
        Manifest.specification(spec)
        if not lock.packages[name] then error("Lockfile is missing a root dependency", 0) end
    end
    for name, p in pairs(lock.packages) do
        count += 1; if count > 256 then error("Too many locked packages", 0) end
        if not Util.name(name) or type(p) ~= "table" or p.name ~= name then error("Unsafe/contradictory lockfile package identity", 0) end
        for _, flag in ipairs({ "external", "localSource" }) do if p[flag] ~= nil and type(p[flag]) ~= "boolean" then error("Invalid lockfile source flag", 0) end end
        SemVer.parse(p.version)
        local localGit = p.localSource == true and type(p.registry) == "string" and path.isAbsolute(p.registry) and type(p.source) == "string" and path.isAbsolute(p.source:sub(5))
        if type(p.source) ~= "string" or p.source:find("%c") or (p.source:sub(1, 5) ~= "path:" and (p.source:sub(1, 4) ~= "git+" or (not Util.url(p.source:sub(5)) and not localGit))) then error("Unsafe lockfile source", 0) end
        if p.source:sub(1, 5) == "path:" then
            if not path.isAbsolute(p.source:sub(6)) or p.revision ~= p.integrity then error("Invalid local snapshot identity", 0) end
        elseif not Util.revision(p.revision) then error("Lockfile needs an immutable Git commit", 0) end
        if not Util.checksum(p.integrity) or not Util.relative(p.entry) or not p.entry:match("%.luau?$") then error("Lockfile is missing verified integrity/entrypoint", 0) end
        if not Json.object(p.dependencies) or not Json.object(p.requirements) then error("Missing lockfile dependency relationships", 0) end
        for child, version in pairs(p.dependencies) do
            if not lock.packages[child] or lock.packages[child].version ~= version or not p.requirements[child] then error("Broken lockfile dependency relationship", 0) end
        end
        for child, spec in pairs(p.requirements) do
            if not Util.name(child) or not p.dependencies[child] then error("Missing resolved dependency", 0) end
            Manifest.specification(spec)
            if not Util.pathSpec(spec) and spec:sub(1, 4) ~= "git+" and not SemVer.satisfies(lock.packages[child].version, spec) then error("Locked dependency violates its version range", 0) end
            if p.source:sub(1, 5) ~= "path:" and (Util.pathSpec(spec) or spec:sub(1, 4) == "git+") then error("Registry/Git packages must depend on registry version ranges", 0) end
            if Util.pathSpec(spec) and lock.packages[child].source ~= "path:" .. Util.localPath(p.source:sub(6), spec) then error("Locked local dependency source does not match its declaration", 0) end
            if spec:sub(1, 4) == "git+" and lock.packages[child].source .. "#" .. lock.packages[child].revision ~= spec then error("Locked Git dependency source does not match its declaration", 0) end
        end
    end
    local visiting, done = {}, {}
    local function visit(name, depth)
        if depth > 128 or visiting[name] then error("Circular or excessively deep lockfile dependency graph", 0) end
        if done[name] then return end
        visiting[name] = true
        for child in pairs(lock.packages[name].dependencies) do visit(child, depth + 1) end
        visiting[name] = nil; done[name] = true
    end
    for name, spec in pairs(lock.roots) do
        local p = lock.packages[name]
        if not Util.pathSpec(spec) and spec:sub(1, 4) ~= "git+" and not SemVer.satisfies(p.version, spec) then error("Locked root violates manifest range", 0) end
        if spec:sub(1, 4) == "git+" and p.source .. "#" .. p.revision ~= spec then error("Locked Git root does not match manifest source", 0) end
        visit(name, 0)
    end
    for name in pairs(lock.packages) do if not done[name] then error("Unreachable package in lockfile: " .. name, 0) end end
    return lock
end
function Lockfile.matches(lock, manifest, directory)
    if not lock or lock.lock_version ~= 2 or Json.encode(lock.roots) ~= Json.encode(manifest.dependencies) then return false end
    for name, spec in pairs(manifest.dependencies) do
        if Util.pathSpec(spec) and lock.packages[name].source ~= "path:" .. Util.localPath(directory, spec) then return false end
    end
    return true
end
function Lockfile.prune(lock, manifest, directory)
    for name, spec in pairs(manifest.dependencies) do
        if lock.roots[name] ~= spec then return nil end
        if Util.pathSpec(spec) and lock.packages[name].source ~= "path:" .. Util.localPath(directory, spec) then return nil end
    end
    local result = { lock_version = 2, roots = table.clone(manifest.dependencies), packages = {} }
    local function visit(name)
        if result.packages[name] then return end
        result.packages[name] = table.clone(lock.packages[name])
        for child in pairs(lock.packages[name].dependencies) do visit(child) end
    end
    for name in pairs(manifest.dependencies) do visit(name) end
    return Lockfile.validate(result)
end
local fields = { "name", "version", "source", "revision", "integrity", "entry", "registry", "external", "localSource", "requirements", "dependencies" }
function Lockfile.render(lock)
    Lockfile.validate(lock)
    local lines = { "lock_version = 2", "roots = " .. Json.encode(Json.encode(lock.roots)) }
    for _, name in ipairs(Util.keys(lock.packages)) do
        table.insert(lines, "\n[packages." .. Json.encode(name) .. "]")
        local p = lock.packages[name]
        for _, field in ipairs(fields) do
            local value = p[field]
            if value ~= nil then table.insert(lines, field .. " = " .. Json.encode(type(value) == "table" and Json.encode(value) or value)) end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end
function Lockfile.load(directory)
    local filename = path.join(directory, "xtpkg.lock"); Util.noLinks(filename)
    if not fs.exists(filename) then return nil end
    if fs.stat(filename):await().size > 4 * 1024 * 1024 then error("Lockfile exceeds size limit", 0) end
    local text = fs.readSync(filename)
    if text:match("^lock_version%s*=%s*1%s") then
        local old = legacyToml.decode(text)
        if type(old.packages) ~= "table" then old.packages = {} end
        for name in pairs(old.packages) do if not Util.name(name) or name:find("/", 1, true) then error("Unsafe legacy lockfile package", 0) end end
        old.legacy = true; return old
    end
    local lock, current, seen = { packages = {} }, nil, {}
    for line in text:gmatch("[^\r\n]+") do
        if line:match("^%s*$") or line:match("^%s*#") then continue end
        local quoted = line:match("^%[packages%.(\".*\")%]$")
        if quoted then
            local name = Json.decode(quoted)
            if not Util.name(name) or lock.packages[name] then error("Duplicate/unsafe locked package", 0) end
            current = {}; lock.packages[name] = current; seen = {}
        else
            local key, value = line:match("^([%w_]+)%s*=%s*(.+)$")
            if not key or seen[key] then error("Malformed or duplicate lockfile field", 0) end
            seen[key] = true
            local decoded = Json.decode(value, 4 * 1024 * 1024)
            if key == "roots" or key == "requirements" or key == "dependencies" then if type(decoded) ~= "string" then error("Invalid locked dependency map", 0) end; decoded = Json.decode(decoded) end
            if current then
                if not table.find(fields, key) then error("Unknown lockfile package field: " .. key, 0) end
                current[key] = decoded
            else
                if key ~= "lock_version" and key ~= "roots" then error("Unknown lockfile header", 0) end
                lock[key] = decoded
            end
        end
    end
    return Lockfile.validate(lock)
end
function Lockfile.save(directory, lock) fs.writeSync(path.join(directory, "xtpkg.lock"), Lockfile.render(lock)) end
return Lockfile
