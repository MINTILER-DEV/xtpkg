-- Exercise the HTTPS transport branch without external services or TLS setup.
local Client = require("../src/registry/Client")
local Json = require("../src/package/Json")
local http = require("net/http")
local Promise = require("async/promise")
local count, calls = 0, 0
local function check(v) count += 1; assert(v, "registry client check " .. count) end
local function bad(fn, message)
    local ok, err = pcall(fn)
    check(not ok and tostring(err):find(message, 1, true) ~= nil)
end
local original = http.fetch
local base = "https://registry-fixture.invalid/test"
local metadata = { name = "ex/http", description = "HTTP fixture", repository = "https://example.invalid/http", versions = { ["1.0.0"] = { source = { type = "git", url = "https://example.invalid/http", revision = string.rep("a", 40) }, dependencies = {} } } }
local bodies = {
    [base .. "/index.json"] = Json.encode({ registry_version = 1, packages = { ["ex/http"] = { path = "packages/ex/http.json" } } }),
    [base .. "/packages/ex/http.json"] = Json.encode(metadata),
}
http.fetch = function(url)
    calls += 1
    return Promise.resolve({ ok = bodies[url] ~= nil, status = bodies[url] and 200 or 404, body = bodies[url] or "not found" })
end
local client = Client.new({ registry = base })
check(client:index().registry_version == 1)
check(client:package("ex/http").versions["1.0.0"].source.revision == string.rep("a", 40))
check(client:package("ex/http").name == "ex/http" and calls == 2)
metadata.versions["1.0.0"].source.revision = string.rep("b", 40)
bodies[base .. "/packages/ex/http.json"] = Json.encode(metadata)
bad(function() Client.new({ registry = base }):package("ex/http") end, "immutable version")
calls = 0
http.fetch = function() calls += 1; return Promise.reject("network should not be reached") end
check(Client.new({ registry = base, offline = true }):package("ex/http").versions["1.0.0"].source.revision == string.rep("a", 40))
check(calls == 0)
bad(function() Client.new({ registry = base .. "/missing", offline = true }):index() end, "metadata is missing")
check(calls == 0)
bad(function() Client.new({ registry = base .. "/unavailable" }):index() end, "Could not retrieve registry metadata")
http.fetch = function() return Promise.resolve({ ok = true, body = string.rep("x", 2 * 1024 * 1024 + 1) }) end
bad(function() Client.new({ registry = base .. "/oversize" }):index() end, "size limit")
http.fetch = function() return Promise.resolve({ ok = true, body = '{"registry_version":1,"packages":{},"packages":{}}' }) end
bad(function() Client.new({ registry = base .. "/duplicate" }):index() end, "Malformed")
http.fetch = original
print("Registry HTTPS/offline transport checks passed: " .. count)
