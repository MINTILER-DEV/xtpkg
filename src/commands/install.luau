local Manifest = require("../package/Manifest")
local Lockfile = require("../package/Lockfile")
local Resolver = require("../package/Resolver")
local Installer = require("../package/Installer")

local install = {}

function install.run(_args)
    local cwd = process.cwd()
    local lock = Resolver.resolve(cwd, Manifest.load(cwd))
    local previousLock = Lockfile.load(cwd)
    Installer.install(cwd, previousLock, lock)
    Lockfile.save(cwd, lock)
    print("Wrote xtpkg.lock")
end

return install
