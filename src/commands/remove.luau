local Manifest = require("../package/Manifest")
local Operations = require("../package/Operations")
local remove = {}
function remove.run(args)
    if not args._[2] or args._[3] then error("Usage: xtpkg remove <package>", 0) end
    Operations.perform(args, function(manifest) Manifest.removeDependency(manifest, args._[2]) end)
    args.log("Removed " .. args._[2] .. "; updated xtpkg.toml and xtpkg.lock")
end
return remove
