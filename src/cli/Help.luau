local Help = {}
Help.version = "0.2.0"
Help.commands = {
    init = "init [name] [--force]                 Create a project and entrypoint",
    add = "add <name[@range]|path|name@git+url#commit> [--allow-git]\n                                        Resolve, install, and save a dependency",
    remove = "remove <name>                          Remove a direct dependency and prune its graph",
    install = "install [--locked|--frozen] [--offline] Install the exact current lock or resolve a new graph",
    list = "list [--tree]                          Show direct dependencies or the full dependency graph",
    run = "run <script>                           Run an explicitly selected project script",
    search = "search [term]                          Search the configured registry index",
    info = "info <name>                            Show package metadata and immutable versions",
    update = "update [name]                          Resolve newer compatible versions and install",
    outdated = "outdated                               Compare locked, compatible, and latest stable versions",
    publish = "publish [--dry-run] [--output file]     Validate committed files and prepare a PR submission",
    cache = "cache <path|list|clean|verify>           Inspect or maintain the shared managed cache",
    config = "config <get registry|set registry URL>  Configure a registry; XTPKG_REGISTRY overrides it",
    help = "help [command]                         Show command help",
    version = "version                                Show XTPKG version",
}
function Help.show(name)
    if name then
        if not Help.commands[name] then error("Unknown command: " .. name, 0) end
        print("Usage: xtpkg " .. Help.commands[name])
    else
        print("XTPKG " .. Help.version .. " — LuauXTX package manager\nUsage: xtpkg <command> [arguments]\n")
        for _, name in ipairs({ "init", "add", "remove", "install", "list", "run", "search", "info", "update", "outdated", "publish", "cache", "config", "help", "version" }) do print("  " .. Help.commands[name]) end
    end
    print("\nGlobal options: --help (-h), --version, --verbose (-v), --quiet (-q), --offline")
    if name == "add" or name == "install" or name == "update" or name == "remove" or name == "info" or name == "outdated" then print("Local registry fixtures: --allow-local-sources opts into absolute local Git sources.") end
    if name == "install" then print("--locked requires a current lock and forbids lock changes; downloads are allowed.\n--frozen also forbids resolution and network; all artifacts must already be verified in cache.") end
end
return Help
