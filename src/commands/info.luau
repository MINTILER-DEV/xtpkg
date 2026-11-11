local Client = require("../registry/Client")
local Util = require("../package/Util")
local SemVer = require("../package/SemVer")
return { run = function(args)
    if not args._[2] or args._[3] then error("Usage: xtpkg info <package>", 0) end
    local p = Client.new(args):package(args._[2])
    print(p.name .. "\n" .. p.description .. "\nRepository: " .. p.repository)
    for _, version in ipairs(SemVer.sort(Util.keys(p.versions))) do print("  " .. version .. "  " .. p.versions[version].source.revision) end
end }
