local fs = require("system/fs")
local path = require("system/path")
local Util = require("./Util")
local Json = require("./Json")
local Manifest = require("./Manifest")
local Cache = require("./Cache")
local Source = {}
local ignored = { [".git"] = true, packages = true, node_modules = true, target = true, local_ = true }
function Source.allowed(filename)
    if not Util.relative(filename) then error("Unsafe package path: " .. tostring(filename), 0) end
    for part in filename:gmatch("[^/]+") do
        local lower = part:lower()
        if ignored[lower] or lower == "local" or lower:sub(1, 6) == ".xtpkg" or lower == ".env" or lower:sub(1, 5) == ".env." then error("Unnecessary or sensitive package file: " .. filename, 0) end
    end
    local ext = filename:lower():match("%.([^.]+)$")
    if ext and ({ dll = true, so = true, dylib = true, exe = true, pem = true, key = true, pfx = true, wasm = true, zip = true, tar = true, gz = true })[ext] then error("Unsupported native, binary, archive, or sensitive package file: " .. filename, 0) end
end
function Source.validate(snapshot, expected)
    if not Json.object(snapshot) or not Json.object(snapshot.files) then error("Malformed package snapshot", 0) end
    local bytes, count, seen = 0, 0, {}
    for filename, contents in pairs(snapshot.files) do
        Source.allowed(filename)
        if seen[filename:lower()] then error("Case-colliding package files", 0) end
        seen[filename:lower()] = true; count += 1
        if type(contents) ~= "string" or #contents > 1024 * 1024 or contents:find("%z") then error("Only UTF-8 text package files up to 1 MiB are supported", 0) end
        if utf8.len(contents) == nil then error("Invalid UTF-8 package file", 0) end
        bytes += #contents
        if count > 2048 or bytes > 16 * 1024 * 1024 then error("Package exceeds 2048 files / 16 MiB limit", 0) end
    end
    for filename in pairs(snapshot.files) do
        local parent = path.dirname(filename)
        while parent ~= "." do
            if seen[parent:lower()] then error("File/directory collision in package", 0) end
            parent = path.dirname(parent)
        end
    end
    local integrity = Util.sha(Json.encode(snapshot.files))
    if snapshot.integrity ~= integrity or (expected and expected.integrity and expected.integrity ~= integrity) then error("Package integrity mismatch; cache/source may be corrupted", 0) end
    local text = snapshot.files["xtpkg.toml"]
    if not text then error("Package is missing xtpkg.toml", 0) end
    local manifest = Manifest.decode(text)
    if not snapshot.files[manifest.package.entry] then error("Package entrypoint is missing: " .. manifest.package.entry, 0) end
    if expected then
        if manifest.package.name ~= expected.name or manifest.package.version ~= expected.version then error("Downloaded package identity/version does not match resolved metadata", 0) end
        if expected.entry and manifest.package.entry ~= expected.entry then error("Package entrypoint contradicts registry metadata", 0) end
        if expected.dependencies and Json.encode(manifest.dependencies) ~= Json.encode(expected.dependencies) then error("Package dependencies contradict registry metadata/lockfile", 0) end
    end
    return manifest
end
function Source.localSnapshot(directory)
    Util.noLinks(directory)
    -- Enumerate OS metadata without following links. fs.stat alone cannot
    -- distinguish symlinks/junctions from their targets in the current runtime.
    local result
    if process.getenv("COMSPEC") then
        result = process.exec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; $q=New-Object 'Collections.Generic.Queue[string]'; $q.Enqueue($env:XTPKG_CHECK_PATH); $n=0; while($q.Count) { foreach($i in Get-ChildItem -LiteralPath $q.Dequeue() -Force) { if($i.Name -in @('.git','packages','node_modules','target','local') -or $i.Name.StartsWith('.xtpkg')) { continue }; if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { exit 2 }; $n++; if($n -gt 4096) { exit 3 }; if($i.PSIsContainer) { $q.Enqueue($i.FullName) } } }" }, { env = { XTPKG_CHECK_PATH = directory } })
    else
        result = process.exec("find", { "-P", directory, "(", "-name", ".git", "-o", "-name", "packages", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", "local", "-o", "-name", ".xtpkg*", ")", "-prune", "-o", "-type", "l", "-print" })
    end
    if result.code ~= 0 or result.stdout ~= "" then error("Local package contains unsafe links or too many files", 0) end
    local files, count, bytes = {}, 0, 0
    local function visit(relative, depth)
        if depth > 32 then error("Package directory depth exceeds limit", 0) end
        for _, name in ipairs(fs.readDir(path.join(directory, relative)):await()) do
            if ignored[name:lower()] or name:lower() == "local" or name:lower():sub(1, 6) == ".xtpkg" then continue end
            local file = relative == "" and name or relative .. "/" .. name; Source.allowed(file)
            local full = path.join(directory, file); local stat = fs.stat(full):await()
            count += 1; if count > 4096 then error("Package contains too many entries", 0) end
            if stat.isDirectory then visit(file, depth + 1)
            elseif stat.isFile then
                bytes += stat.size
                if stat.size > 1024 * 1024 or bytes > 16 * 1024 * 1024 then error("Local package exceeds text size limit", 0) end
                files[file] = fs.readSync(full)
            else error("Unsupported package filesystem entry: " .. file, 0) end
        end
    end
    visit("", 0)
    local snapshot = { files = files, integrity = Util.sha(Json.encode(files)) }
    Source.validate(snapshot); return snapshot
end
function Source.gitSnapshot(url, revision, temporaryBase, allowLocal)
    if not Util.revision(revision) or (not Util.url(url) and not (allowLocal and path.isAbsolute(url))) then error("Git source requires a safe HTTPS URL and exact commit", 0) end
    Util.noLinks(temporaryBase); Util.mkdir(temporaryBase)
    local work = path.join(temporaryBase, ".xtpkg-fetch-" .. Util.id()); Util.mkdir(work)
    local snapshot
    local ok, err = pcall(function()
        Util.git({ "init", "--bare", "." }, work)
        Util.git({ "fetch", "--no-tags", "--depth=1", "--", url, revision }, work)
        local actual = Util.git({ "rev-parse", "FETCH_HEAD^{commit}" }, work):match("^%x+")
        if actual ~= revision then error("Git fetch returned a different commit", 0) end
        local listing = Util.git({ "ls-tree", "-r", "-l", "-z", "--full-tree", revision }, work)
        if #listing > 1024 * 1024 then error("Git package tree exceeds size limit", 0) end
        local files, bytes, count = {}, 0, 0
        for line in listing:gmatch("([^%z]+)%z") do
            local mode, objectType, oid, size, filename = line:match("^(%d+) (%w+) (%x+)%s+(%d+)\t(.+)$")
            if not filename or objectType ~= "blob" or (mode ~= "100644" and mode ~= "100755") then error("Git package contains a symlink, submodule, or unsupported tree entry", 0) end
            Source.allowed(filename); count += 1; bytes += tonumber(size)
            if count > 2048 or tonumber(size) > 1024 * 1024 or bytes > 16 * 1024 * 1024 then error("Git package exceeds text size limit", 0) end
            local contents = Util.git({ "cat-file", "blob", oid }, work)
            -- process.exec decodes UTF-8. Hash the returned bytes with Git to
            -- ensure no lossy conversion occurred before trusting the commit.
            local check = path.join(work, "xtpkg-blob-check")
            fs.writeSync(check, contents)
            local got = Util.git({ "hash-object", "--no-filters", "--", check }, work):match("^%x+")
            if got ~= oid then error("Git package contains unsupported non-UTF-8 content", 0) end
            files[filename] = contents
        end
        snapshot = { files = files, integrity = Util.sha(Json.encode(files)) }
        Source.validate(snapshot)
    end)
    Util.remove(work)
    if not ok then error(err, 0) end
    return snapshot
end
function Source.obtain(package, options)
    options = options or {}
    local key = Cache.packageKey(package)
    local snapshot = Cache.read("packages", key, 64 * 1024 * 1024)
    local expected = { name = package.name, version = package.version, entry = package.entry, integrity = package.integrity, dependencies = package.requirements }
    if snapshot then Source.validate(snapshot, expected); return snapshot end
    if options.offline or options.frozen then error("Verified cached artifact is missing for " .. package.name .. "@" .. package.version, 0) end
    if package.source:sub(1, 5) == "path:" then snapshot = Source.localSnapshot(package.source:sub(6))
    else
        if package.localSource and not options["allow-local-sources"] then error("Local Git fixtures require --allow-local-sources", 0) end
        snapshot = Source.gitSnapshot(package.source:sub(5), package.revision, Cache.root(true), package.localSource == true)
    end
    Source.validate(snapshot, expected); Cache.write("packages", key, snapshot); return snapshot
end
return Source
