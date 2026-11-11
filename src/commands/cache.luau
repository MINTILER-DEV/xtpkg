local Cache = require("../package/Cache")
local Source = require("../package/Source")
local Metadata = require("../registry/Metadata")
return { run = function(args)
    local action = args._[2]
    if args._[3] then error("Usage: xtpkg cache <path|list|verify|clean>", 0) end
    if action == "path" then print(Cache.root(false))
    elseif action == "list" then for _, entry in ipairs(Cache.entries()) do print(entry.kind .. "  " .. entry.file) end
    elseif action == "verify" then print("Verified " .. Cache.verify(Source.validate, function(data, key)
        if key:sub(-11) == "/index.json" then Metadata.index(data) else Metadata.validate(data, data.name, true) end
    end) .. " cache entries")
    elseif action == "clean" then args.log("Removed " .. Cache.clean() .. " managed cache entries")
    else error("Usage: xtpkg cache <path|list|verify|clean>", 0) end
end }
