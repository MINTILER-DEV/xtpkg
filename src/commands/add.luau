local Manifest = require("../package/Manifest")
local Util = require("../package/Util")
local Operations = require("../package/Operations")
local add = {}
function add.run(args)
    local requested = args._[2]
    if not requested or args._[3] then error("Usage: xtpkg add <name[@range]|local-path|name@git+url#commit>", 0) end
    local name, spec = requested:match("^([^@]+)@(.+)$")
    if not name then
        if Util.pathSpec(requested) then
            name = Manifest.load(Util.localPath(process.cwd(), requested)).package.name
            spec = requested:sub(1, 5) == "path:" and requested or "path:" .. requested
        else name, spec = requested, "*" end
    elseif Util.pathSpec(spec) and spec:sub(1, 5) ~= "path:" then spec = "path:" .. spec end
    Operations.perform(args, function(manifest) Manifest.addDependency(manifest, name, spec) end)
    args.log("Updated xtpkg.toml and xtpkg.lock")
end
return add
