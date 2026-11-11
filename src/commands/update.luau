local Manifest = require("../package/Manifest")
local Operations = require("../package/Operations")
return { run = function(args)
    if args._[3] then error("Usage: xtpkg update [package]", 0) end
    local target = args._[2]
    if target and not Manifest.load(process.cwd()).dependencies[target] then error("Not a direct dependency: " .. target, 0) end
    Operations.perform(args, nil, target or true)
    args.log("Updated compatible dependencies and xtpkg.lock")
end }
