local Manifest = require("../package/Manifest")

local run = {}

function run.run(args)
    local script = args._[2]
    if not script or args._[3] then error("Usage: xtpkg run <script>", 0) end
    local manifest = Manifest.load(process.cwd())
    local command = manifest.scripts[script]
    if not command then error("Script not found: " .. script, 0) end
    local shell = process.getenv("COMSPEC")
    local result
    if shell then
        result = process.exec(shell, { "/d", "/s", "/c", command }, { cwd = process.cwd() })
    else
        result = process.exec("sh", { "-c", command }, { cwd = process.cwd() })
    end
    if result.stdout ~= "" then print(result.stdout) end
    if result.stderr ~= "" then print(result.stderr) end
    if result.code ~= 0 then error("Script " .. script .. " exited with status " .. result.code, 0) end
end

return run
