local Manifest = require("../package/Manifest")

local remove = {}

function remove.run(args)
    local name = args._[2]
    if not name then error("Usage: xtpkg remove <package>") end
    local cwd = process.cwd()
    local manifest = Manifest.load(cwd)
    Manifest.removeDependency(manifest, name)
    Manifest.save(cwd, manifest)
    print("Removed " .. name)
end

return remove
