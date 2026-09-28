local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("../package/Manifest")

local init = {}

function init.run(args)
    local cwd = process.cwd()
    Manifest.create(cwd, { name = args._[2] or path.basename(cwd), force = args.force or args.f })
    local src = path.join(cwd, "src")
    if not fs.exists(src) then fs.mkdir(src, true):await() end
    local entry = path.join(src, "main.luau")
    if not fs.exists(entry) then
        fs.writeSync(entry, "print(\"Hello from LuauXTX!\")\n")
    end
    print("Created xtpkg.toml")
end

return init
