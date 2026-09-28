local Manifest = require("../package/Manifest")

local run = {}

function run.run(args)
    local script = args._[2]
    if not script then error("Usage: xtpkg run <script>") end
    local manifest = Manifest.load(process.cwd())
    if not manifest.scripts[script] then error("Script not found: " .. script) end
    error("LuauXTX does not currently expose a child-process API, so xtpkg run cannot execute scripts yet.")
end

return run
