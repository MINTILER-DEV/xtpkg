local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("./Manifest")
local Lockfile = require("./Lockfile")
local Resolver = require("./Resolver")
local Installer = require("./Installer")
local Util = require("./Util")
local Operations = {}
function Operations.perform(options, edit, update)
    options = options or {}
    local directory = process.cwd()
    local guard = path.join(directory, ".xtpkg-operation"); Util.noLinks(guard)
    local acquired = pcall(function() fs.mkdir(guard, false):await() end)
    if not acquired then error("Another XTPKG operation is running, or .xtpkg-operation is left after an interruption. Remove it only after confirming no operation is active.", 0) end
    local result
    local ok, err = pcall(function()
        local manifest = Manifest.load(directory)
        local previous = Lockfile.load(directory)
        if edit and (options.locked or options.frozen) then error("Manifest edits cannot be combined with --locked or --frozen", 0) end
        if edit then edit(manifest) end
        local matches = previous and not previous.legacy and Lockfile.matches(previous, manifest, directory)
        if (options.locked or options.frozen) and (not matches or update) then error("--locked/--frozen requires an existing current v2 lockfile; run xtpkg install first", 0) end
        local lock
        if matches and not update then lock = previous
        elseif edit and previous and not previous.legacy and not update then lock = Lockfile.prune(previous, manifest, directory)
        end
        if not lock then
            if options.frozen then error("--frozen forbids dependency resolution", 0) end
            if options.log then options.log("Resolving dependencies...") end
            local resolveOptions = table.clone(options); resolveOptions.previous = previous and not previous.legacy and previous or nil; resolveOptions.update = update
            lock = Resolver.resolve(directory, manifest, resolveOptions)
        end
        for _, p in pairs(lock.packages) do
            if p.external and not options["allow-git"] then error("External Git dependencies require --allow-git, including locked/offline installs", 0) end
            if p.localSource and not options["allow-local-sources"] then error("Local registry Git sources require --allow-local-sources, including locked/offline installs", 0) end
        end
        local installOptions = table.clone(options)
        installOptions.locked = options.locked or options.frozen
        installOptions.offline = options.offline or options.frozen
        if edit then installOptions.manifestText = Manifest.render(manifest) end
        Installer.install(directory, previous, lock, installOptions)
        result = lock
    end)
    fs.remove(guard):await()
    if not ok then error(err, 0) end
    return result
end
return Operations
