local R = require("../src/package/Resolver")
local M = require("../src/package/Manifest")
local L = require("../src/package/Lockfile")
local J = require("../src/package/Json")
local V = require("../src/registry/Metadata")
local count = 0
local function check(x) count += 1; assert(x, "resolver check " .. count) end
local function fails(fn, match)
    local ok, err = pcall(fn); check(not ok and tostring(err):find(match, 1, true) ~= nil)
end
local revision = string.rep("a", 40)
local function record(deps)
    return { source = { type = "git", url = "https://example.com/repo", revision = revision }, dependencies = deps or {}, entry = "init.luau", integrity = string.rep("b", 64) }
end
local data = {
    ["ex/a"] = { name = "ex/a", description = "A", repository = "https://example.com/a", versions = { ["1.0.0"] = record({ ["ex/shared"] = "^1.0.0" }), ["2.0.0"] = record({ ["ex/shared"] = "^2.0.0" }) } },
    ["ex/b"] = { name = "ex/b", description = "B", repository = "https://example.com/b", versions = { ["1.0.0"] = record({ ["ex/shared"] = "^1.0.0" }) } },
    ["ex/shared"] = { name = "ex/shared", description = "S", repository = "https://example.com/s", versions = { ["1.0.0"] = record(), ["1.9.0"] = record(), ["2.0.0"] = record(), ["3.0.0-beta"] = record() } },
}
local reads = 0
local client = { base = "fixture", package = function(_, name) reads += 1; if not data[name] then error("Missing package " .. name, 0) end; return V.validate(data[name], name) end }
local function manifest(deps) return M.validate({ package = { name = "app", version = "1.0.0", entry = "src/main.luau" }, dependencies = deps }) end
local function resolve(deps, options) options = options or {}; options.client = client; return R.resolve(process.cwd(), manifest(deps), options) end
local lock = resolve({ ["ex/a"] = "*", ["ex/b"] = "*" })
check(lock.packages["ex/a"].version == "1.0.0") -- backtrack from 2.0
check(lock.packages["ex/shared"].version == "1.9.0")
check(lock.packages["ex/a"].dependencies["ex/shared"] == "1.9.0")
local rendered = L.render(lock)
check(rendered == L.render(resolve({ ["ex/b"] = "*", ["ex/a"] = "*" })))
fails(function() resolve({ ["ex/a"] = "^2.0.0", ["ex/b"] = "*" }) end, "app -> ex/b@* -> ex/shared@^1.0.0")
fails(function() resolve({ missing = "*" }) end, "Missing package missing")
fails(function() resolve({ ["ex/a"] = "^9.0.0" }) end, "no version/source satisfies")
data["ex/shared"].versions["1.9.0"].dependencies = { ["ex/b"] = "*" }
data["ex/shared"].versions["1.0.0"].dependencies = { ["ex/b"] = "*" }
fails(function() resolve({ ["ex/b"] = "*" }) end, "Circular dependency")
data["ex/shared"].versions["1.9.0"].dependencies = {}; data["ex/shared"].versions["1.0.0"].dependencies = {}
local prev = resolve({ ["ex/shared"] = "1.0.0" })
check(resolve({ ["ex/shared"] = "*" }, { previous = prev }).packages["ex/shared"].version == "1.0.0")
check(resolve({ ["ex/shared"] = "*" }, { previous = prev, update = true }).packages["ex/shared"].version == "2.0.0")
check(resolve({ ["ex/shared"] = ">=3.0.0-beta" }).packages["ex/shared"].version == "3.0.0-beta")
fails(function() M.decode('[package]\nname = "../bad"\nversion="1.0.0"\nentry="main.luau"') end, "Invalid package.name")
fails(function() M.decode('[package]\nname="a"\nversion="01.0.0"\nentry="main.luau"') end, "Invalid semantic version")
fails(function() M.decode('[package]\nname="a"\nversion="1.0.0"\nentry="../main.luau"') end, "safe relative")
fails(function() V.index({ registry_version = 1, packages = { bad = { path = "../a.json" } } }) end, "Unsafe")
local invalid = J.decode(J.encode(data["ex/a"])); invalid.versions["1.0.0"].source.revision = "main"
fails(function() V.validate(invalid, "ex/a") end, "immutable")
invalid = J.decode(J.encode(data["ex/a"])); invalid.versions["1.0.0"].dependencies = { bad = "path:../x" }
fails(function() V.validate(invalid, "ex/a") end, "Registry dependencies")
local corrupt = J.decode(J.encode(lock)); corrupt.packages["ex/shared"].version = "1.0.0"
fails(function() L.validate(corrupt) end, "relationship")
check(L.matches(lock, manifest(lock.roots), process.cwd()))
print("Resolver/manifest/metadata checks passed: " .. count)
