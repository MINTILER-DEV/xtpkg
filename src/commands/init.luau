local fs = require("system/fs")
local path = require("system/path")
local Manifest = require("../package/Manifest")

local init = {}

function init.run(args)
    local cwd = process.cwd()

    if Manifest.exists(cwd) and not args.force and not args.f then
        error("xtpkg.toml already exists (use --force to overwrite)")
    end

    -- `xtpkg init my-app`
    -- otherwise use the current directory name
    Manifest.create(cwd, {
        name = args._[2] or path.basename(cwd),
        force = args.force or args.f,
    })

    -- optional starter source
    local src = path.join(cwd, "src")

    if not fs.exists(src) then
        fs.mkdir(src)
    end

    local entry = path.join(src, "main.luau")

    if not fs.exists(entry) then
        fs.writeFile(entry, [[
        print("Hello from LuauXTX!")
        ]])
    end

    print("Created xtpkg.toml")
end

return init
