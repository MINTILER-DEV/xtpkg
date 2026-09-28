local Manifest = require("../package/Manifest")
local Lockfile = require("../package/Lockfile")

local list = {}

function list.run(_args)
    local cwd = process.cwd()
    local manifest, lock = Manifest.load(cwd), Lockfile.load(cwd)
    local names = {}
    for name in pairs(manifest.dependencies) do table.insert(names, name) end
    table.sort(names)
    if #names == 0 then print("No dependencies.") return end
    for _, name in ipairs(names) do
        local resolved = lock.packages[name]
        print(name .. " " .. manifest.dependencies[name] .. (resolved and " -> " .. resolved.version or " (not installed)"))
    end
end

return list
