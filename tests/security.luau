local A = require("../src/cli/args")
local Source = require("../src/package/Source")
local U = require("../src/package/Util")
local J = require("../src/package/Json")
local count = 0
local function check(v) count += 1; assert(v, "security/CLI check " .. count) end
local function bad(fn) check(not pcall(fn)) end
local a = A.parse({ "publish", "--output", "submission.json", "--dry-run", "-qv" })
check(a._[1] == "publish" and a.output == "submission.json" and a["dry-run"] and a.quiet and a.verbose)
check(A.parse({ "publish", "--output=x.json" }).output == "x.json")
check(A.parse({ "search", "--", "-hello" })._[2] == "-hello")
for _, values in ipairs({ { "--output" }, { "--output", "--quiet" }, { "--offline=false" }, { "--unknown" }, { "-z" } }) do bad(function() A.parse(values) end) end
local function snapshot(extra)
    local files = { ["xtpkg.toml"] = '[package]\nname="ex/a"\nversion="1.0.0"\nentry="init.luau"\n[dependencies]\n', ["init.luau"] = "return {}\n" }
    for k, v in pairs(extra or {}) do files[k] = v end
    return { files = files, integrity = U.sha(J.encode(files)) }
end
check(Source.validate(snapshot()).package.name == "ex/a")
for _, file in ipairs({ "../escape", "a\\b", "a/nul.txt", "a/CON", "packages/a", "node_modules/a", ".env", ".env.production", "private.pem", "native.dll", "archive.zip", "a/../b", "a:b", "a/b.", "Ä.luau", "LONGFI~1", "conin$" }) do bad(function() Source.validate(snapshot({ [file] = "x" })) end) end
bad(function() Source.validate(snapshot({ ["README"] = "a", ["readme"] = "b" })) end)
bad(function() Source.validate(snapshot({ ["a"] = "x", ["a/b"] = "y" })) end)
bad(function() Source.validate(snapshot({ ["binary"] = "a\0b" })) end)
bad(function() Source.validate(snapshot({ ["invalid"] = string.char(255) })) end)
bad(function() Source.validate(snapshot(), { name = "ex/b", version = "1.0.0" }) end)
bad(function() Source.validate(snapshot(), { name = "ex/a", version = "2.0.0" }) end)
bad(function() Source.validate(snapshot(), { name = "ex/a", version = "1.0.0", integrity = string.rep("a", 64) }) end)
print("Security/CLI checks passed: " .. count)
