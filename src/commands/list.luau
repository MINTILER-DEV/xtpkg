local Manifest = require("../package/Manifest")
local Lockfile = require("../package/Lockfile")
local Util = require("../package/Util")
return { run = function(args)
    if args._[2] then error("Usage: xtpkg list [--tree]", 0) end
    local manifest = Manifest.load(process.cwd()); local lock = Lockfile.load(process.cwd())
    local names = Util.keys(manifest.dependencies)
    if #names == 0 then print("No dependencies."); return end
    local shown = {}
    local function display(name, prefix, spec)
        local p = lock and lock.packages[name]
        print(prefix .. name .. (spec and " " .. spec or "") .. (p and " -> " .. p.version or " (not installed)"))
        if args.tree and p and p.dependencies then
            if shown[name] then print(prefix .. "  (shared; shown above)"); return end
            shown[name] = true
            for _, child in ipairs(Util.keys(p.dependencies)) do display(child, prefix .. "  ", p.requirements[child]) end
        end
    end
    for _, name in ipairs(names) do display(name, "", manifest.dependencies[name]) end
end }
