local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("../package/Manifest")

local init = {}

function init.run(args)
    local cwd = process.cwd()
    Manifest.create(cwd, { name = args._[2] or path.basename(cwd), force = args.force or args.f })
    print("Created xtpkg.toml")
    if not fs.exists(path.join(cwd, "src/main.luau")) then
        print("Create src/main.luau to use the default start script (this LuauXTX runtime cannot create directories).")
    end
end

return init
