local fs = require("system/fs")
local path = require("system/path")
local Toml = require("./Toml")
local Util = require("./Util")
local SemVer = require("./SemVer")
local Manifest = {}

function Manifest.specification(spec, registryOnly)
    if type(spec) ~= "string" or #spec == 0 or #spec > 2048 or spec:find("%c") then error("Invalid dependency specification", 0) end
    if Util.pathSpec(spec) then
        if registryOnly then error("Registry dependencies must use version ranges; local paths are private-project only", 0) end
        if spec == "path:" then error("Empty path dependency", 0) end
    elseif spec:sub(1, 4) == "git+" then
        local url, revision = spec:match("^git%+(.+)#([0-9a-f]+)$")
        if registryOnly or not Util.url(url) or not Util.revision(revision) then error("Git dependencies require git+https://host/repository#<40 lowercase hex commit> and --allow-git", 0) end
    else SemVer.range(spec) end
end
function Manifest.validate(manifest)
    if type(manifest) ~= "table" or type(manifest.package) ~= "table" then error("xtpkg.toml is missing [package]", 0) end
    local p = manifest.package
    if not Util.name(p.name) then error("Invalid package.name; use name or scope/name with lowercase letters, digits, hyphens, and underscores", 0) end
    SemVer.parse(p.version)
    if not Util.relative(p.entry) or not p.entry:match("%.luau?$") then error("package.entry must be a safe relative .lua or .luau file", 0) end
    for _, key in ipairs({ "description", "license", "repository" }) do
        if p[key] ~= nil and (type(p[key]) ~= "string" or #p[key] == 0 or #p[key] > 4096) then error("package." .. key .. " must be a non-empty string", 0) end
    end
    if p.repository ~= nil and not Util.url(p.repository) then error("package.repository must be a credential-free HTTPS repository URL", 0) end
    for _, section in ipairs({ "dependencies", "scripts" }) do
        manifest[section] = manifest[section] or {}
        if type(manifest[section]) ~= "table" then error(section .. " must be a table", 0) end
        local count = 0
        for key, value in pairs(manifest[section]) do
            count += 1
            if count > 256 then error("Too many " .. section .. " declarations (limit 256)", 0) end
            if type(key) ~= "string" or key == "" or type(value) ~= "string" or value == "" then error("Invalid " .. section .. " declaration", 0) end
            if section == "dependencies" then
                if not Util.name(key) then error("Invalid dependency name: " .. key, 0) end
                Manifest.specification(value)
            end
        end
    end
    return manifest
end
function Manifest.decode(text)
    local manifest = Manifest.validate(Toml.decode(text)); manifest._text = text; return manifest
end
function Manifest.exists(directory) return fs.exists(path.join(directory, "xtpkg.toml")) end
function Manifest.load(directory)
    local filename = path.join(directory, "xtpkg.toml")
    Util.noLinks(filename)
    if not fs.exists(filename) then error("No xtpkg.toml found in " .. directory, 0) end
    if fs.stat(filename):await().size > 1024 * 1024 then error("xtpkg.toml exceeds size limit", 0) end
    return Manifest.decode(fs.readSync(filename))
end
function Manifest.render(manifest)
    Manifest.validate(manifest)
    if manifest._text then return Toml.dependencies(manifest._text, manifest.dependencies) end
    local lines = {}
    for _, section in ipairs({ "package", "dependencies", "scripts" }) do
        table.insert(lines, "[" .. section .. "]")
        for _, key in ipairs(Util.keys(manifest[section])) do
            local v = manifest[section][key]
            table.insert(lines, Toml.quote(key) .. " = " .. (type(v) == "string" and Toml.quote(v) or tostring(v)))
        end
        table.insert(lines, "")
    end
    return table.concat(lines, "\n")
end
function Manifest.save(directory, manifest) fs.writeSync(path.join(directory, "xtpkg.toml"), Manifest.render(manifest)) end
function Manifest.create(directory, options)
    options = options or {}
    if Manifest.exists(directory) and not options.force then error("xtpkg.toml already exists (use --force to overwrite)", 0) end
    local manifest = { package = { name = options.name or path.basename(directory), version = "0.1.0", entry = "src/main.luau" }, dependencies = {}, scripts = { start = "luauxtx src/main.luau" } }
    Manifest.save(directory, manifest); return manifest
end
function Manifest.addDependency(manifest, name, specification)
    if not Util.name(name) then error("Invalid dependency name: " .. tostring(name), 0) end
    Manifest.specification(specification); manifest.dependencies[name] = specification
end
function Manifest.removeDependency(manifest, name)
    if not manifest.dependencies[name] then error("Dependency not found: " .. tostring(name), 0) end
    manifest.dependencies[name] = nil
end
return Manifest
