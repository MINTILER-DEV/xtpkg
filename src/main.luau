-- XTPKG CLI entrypoint
-- main.luau

local args = require("cli/args")

local commands = {
    init = require("./commands/init"),
    add = require("./commands/add"),
    remove = require("./commands/remove"),
    install = require("./commands/install"),
    list = require("./commands/list"),
    run = require("./commands/run"),
}

local parsed = args.parse({...})
local commandName = parsed._[1]

if commandName == nil or commandName == "help" or parsed.help or parsed.h then
    print("Usage: xtpkg <init|add|remove|install|list|run> [arguments]")
    return
end

local command = commands[commandName]
if not command then error("Unknown command: " .. tostring(commandName) .. ". Run xtpkg help for usage.") end
command.run(parsed)
