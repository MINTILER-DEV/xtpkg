local Config = require("../package/Config")
return { run = function(args)
    local action, key, value = args._[2], args._[3], args._[4]
    if action == "get" and key == "registry" and not value then print(Config.registry())
    elseif action == "set" and key and value and not args._[5] then Config.set(key, value); args.log("Saved registry configuration (XTPKG_REGISTRY takes precedence)")
    else error("Usage: xtpkg config get registry | xtpkg config set registry <HTTPS base URL or local directory>", 0) end
end }
