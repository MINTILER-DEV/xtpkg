local Operations = require("../package/Operations")
return { run = function(args)
    if args._[2] then error("Usage: xtpkg install [--locked|--frozen] [--offline]", 0) end
    Operations.perform(args)
    args.log((args.locked or args.frozen) and "Reproduced xtpkg.lock" or "Updated xtpkg.lock")
end }
