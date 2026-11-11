local Client = require("../registry/Client")
local Util = require("../package/Util")
return { run = function(args)
    if args._[3] then error("Usage: xtpkg search [term]", 0) end
    local index, term, count = Client.new(args):index(), (args._[2] or ""):lower(), 0
    for _, name in ipairs(Util.keys(index.packages)) do
        local description = index.packages[name].description or ""
        if name:find(term, 1, true) or description:lower():find(term, 1, true) then print(name .. "  " .. description); count += 1 end
    end
    if count == 0 then print("No matching packages.") end
end }
