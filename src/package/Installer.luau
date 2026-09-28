local fs = require("system/fs")
local path = require("system/path")

local Installer = {}

function Installer.install(directory, lock)
    local packagesDirectory = path.join(directory, "packages")
    if next(lock.packages) == nil then return end
    if not fs.exists(packagesDirectory) then
        error("LuauXTX cannot create the packages directory yet. Create " .. packagesDirectory .. " and run install again.")
    end
    error("LuauXTX does not yet expose directory-copy or link APIs, so local packages cannot be materialized. Dependencies were resolved but not installed.")
end

return Installer
