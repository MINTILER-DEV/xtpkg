local Client = require("../registry/Client")
local Manifest = require("../package/Manifest")
local Lockfile = require("../package/Lockfile")
local Util = require("../package/Util")
local SemVer = require("../package/SemVer")
return { run = function(args)
    if args._[2] then error("Usage: xtpkg outdated", 0) end
    local manifest, lock = Manifest.load(process.cwd()), Lockfile.load(process.cwd())
    local client, count = nil, 0
    for _, name in ipairs(Util.keys(manifest.dependencies)) do
        local spec = manifest.dependencies[name]
        if Util.pathSpec(spec) or spec:sub(1, 4) == "git+" then continue end
        client = client or Client.new(args)
        local versions = SemVer.sort(Util.keys(client:package(name).versions)); local compatible, latest
        for _, v in ipairs(versions) do
            if not latest and not SemVer.parse(v).pre then latest = v end
            if not compatible and SemVer.satisfies(v, spec) then compatible = v end
        end
        local current = lock and lock.packages[name] and lock.packages[name].version
        if not current or (compatible and SemVer.compare(compatible, current) > 0) or (latest and SemVer.compare(latest, current) > 0) then
            if count == 0 then print("PACKAGE  CURRENT  COMPATIBLE  LATEST-STABLE") end
            print(name .. "  " .. (current or "uninstalled") .. "  " .. (compatible or "none") .. "  " .. (latest or "none")); count += 1
        end
    end
    if count == 0 then print("All registry dependencies are up to date.") end
end }
