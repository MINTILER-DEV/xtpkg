local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("../package/Manifest")
local Util = require("../package/Util")

local init = {}

function init.run(args)
    if args._[3] then error("Usage: xtpkg init [name] [--force]", 0) end
    local cwd = process.cwd()
    local src = path.join(cwd, "src")
    local entry = path.join(src, "main.luau")
    Util.noLinks(src); Util.noLinks(entry)
    Manifest.create(cwd, { name = args._[2] or path.basename(cwd), force = args.force or args.f })
    if not fs.exists(src) then fs.mkdir(src, true):await() end
    if not fs.exists(entry) then
        fs.writeSync(entry, "print(\"Hello from LuauXTX!\")\n")
    end
    args.log("Created xtpkg.toml")
end

return init
