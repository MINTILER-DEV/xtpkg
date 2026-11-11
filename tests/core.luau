local S = require("../src/package/SemVer")
local U = require("../src/package/Util")
local J = require("../src/package/Json")
local T = require("../src/package/Toml")
local count = 0
local function check(value) count += 1; assert(value, "check " .. count) end
local function bad(fn) check(not pcall(fn)) end
local ordered = { "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0" }
for i = 2, #ordered do check(S.compare(ordered[i - 1], ordered[i]) == -1) end
check(S.compare("1.10.0", "1.9.0") > 0)
check(S.compare("1.2.3+abc", "1.2.3+123") == 0)
check(S.compare("999999999999999999999.0.0", "999999999999999999998.0.0") > 0)
for _, v in ipairs({ "01.0.0", "1.0", "1.0.0-01", "1.0.0-", "1.0.0+", "1.0.0-a..b", "1.0.0+a+b", "v1.0.0" }) do bad(function() S.parse(v) end) end
for _, r in ipairs({ "1.2.3", "^1.2.3", "~1.2.3", ">=1.2.0", "<2.0.0", ">=1.0.0 <2.0.0", "1.2.x", "*" }) do check(S.satisfies("1.2.3", r)) end
check(not S.satisfies("2.0.0", "^1.2.3")); check(not S.satisfies("1.3.0", "~1.2.3"))
check(S.satisfies("0.2.9", "^0.2.3")); check(not S.satisfies("0.3.0", "^0.2.3"))
check(not S.satisfies("0.0.4", "^0.0.3")); check(not S.satisfies("1.2.4-beta.1", "*"))
check(S.satisfies("1.2.3-beta.2", ">=1.2.3-beta.1 <2.0.0")); check(not S.satisfies("1.3.0-beta", ">=1.2.3-beta.1"))
bad(function() S.range(" ") end); bad(function() S.range("^1.2.x") end)
for _, n in ipairs({ "abc", "example/json", "some_name/x-2" }) do check(U.name(n)) end
for _, n in ipairs({ "../evil", "a/b/c", "A/json", "a/", "con", "a/nul", "a.b" }) do check(not U.name(n)) end
for _, p in ipairs({ "../evil", "/tmp/x", "C:/evil", "a\\b", "a/../b", "a//b", "a/nul.txt", "a/b.", "." }) do check(not U.relative(p)) end
check(U.relative("src/main.luau"))
check(J.decode('{"x":"\\u0061\\ud83d\\ude00","b":false}').x == "a😀")
check(J.encode(J.decode('{"b":false,"a":{}}')) == '{"a":{},"b":false}')
for _, s in ipairs({ '{"a":1,"a":2}', '{"a":}', '{"x":01}', '{"x":1.}', '{"x":1e}', '{"x":"\\q"}', '{}x', '[1,]', '{"a":null,"a":2}' }) do bad(function() J.decode(s) end) end
local text = '# keep\n[package]\nname = "app" # note\nversion = "1.0.0"\nentry = "src/main.luau"\n[dependencies]\n"example/json" = "^1.0.0"\n[custom]\nitems = [1, 2]\n'
check(T.decode(text).dependencies["example/json"] == "^1.0.0")
local edited = T.dependencies(text, { abc = "*" })
check(edited:find('items = [1, 2]', 1, true) ~= nil); check(edited:find('name = "app" # note', 1, true) ~= nil)
check(T.decode(edited).dependencies.abc == "*")
bad(function() T.decode('[package]\nname = "a"\nname = "b"') end)
bad(function() T.decode('[package]\nname = unquoted') end)
print("Core checks passed: " .. count)
