-- XTPKG CLI: retain LuauXTX's script-argument entrypoint and native process API.
local Args = require("./cli/args")
local Help = require("./cli/Help")
local commandRequire = require
local incoming = { ... }
local parsed
local ok, err = xpcall(function()
    parsed = Args.parse(incoming)
    local name = parsed._[1]
    if parsed.version or name == "version" then print("xtpkg " .. Help.version); return end
    if name == "help" then Help.show(parsed._[2]); return end
    if not name or parsed.help or parsed.h then Help.show(name); return end
    if not Help.commands[name] then error("Unknown command: " .. name .. ". Run xtpkg help.", 0) end
    local validOptions = {
        init = { force = true, f = true }, add = { ["allow-git"] = true, ["allow-local-sources"] = true }, remove = { ["allow-git"] = true, ["allow-local-sources"] = true }, install = { locked = true, frozen = true, ["allow-git"] = true, ["allow-local-sources"] = true },
        list = { tree = true }, run = {}, search = { ["allow-local-sources"] = true }, info = { ["allow-local-sources"] = true }, update = { ["allow-git"] = true, ["allow-local-sources"] = true }, outdated = { ["allow-local-sources"] = true }, publish = { ["dry-run"] = true, output = true }, cache = {}, config = {},
    }
    for key in pairs(parsed) do
        if key ~= "_" and key ~= "verbose" and key ~= "quiet" and key ~= "offline" and not validOptions[name][key] then error("Option --" .. key .. " is not supported by " .. name, 0) end
    end
    parsed.log = function(message) if not parsed.quiet then print(message) end end
    commandRequire("./commands/" .. name).run(parsed)
end, function(e)
    if parsed and parsed.verbose then return debug.traceback(tostring(e), 2) end
    return tostring(e):gsub("\nstack traceback:.*", "")
end)
if not ok then
    print("error: " .. tostring(err))
    process.exit(1)
end
