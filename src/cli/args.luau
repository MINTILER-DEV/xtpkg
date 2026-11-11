local Args = {}
local bools = { help = true, h = true, version = true, verbose = true, quiet = true, offline = true, locked = true, frozen = true, ["dry-run"] = true, tree = true, force = true, f = true, ["allow-git"] = true, ["allow-local-sources"] = true }
local values = { output = true }
function Args.parse(valuesIn)
    local result, positional = { _ = {} }, false
    local i = 1
    while i <= #valuesIn do
        local value = valuesIn[i]
        if value == "--" then positional = true
        elseif not positional and value:sub(1, 2) == "--" then
            local key, assigned = value:sub(3):match("^([^=]+)=(.*)$"); key = key or value:sub(3)
            if values[key] then
                if assigned == nil then i += 1; assigned = valuesIn[i] end
                if not assigned or assigned == "" or assigned:sub(1, 1) == "-" then error("--" .. key .. " requires a value", 0) end
                result[key] = assigned
            elseif bools[key] then
                if assigned ~= nil then error("--" .. key .. " does not take a value", 0) end
                result[key] = true
            else error("Unknown option: --" .. key, 0) end
        elseif not positional and value:sub(1, 1) == "-" and #value > 1 then
            for c in value:sub(2):gmatch(".") do
                if c == "h" or c == "f" then result[c] = true
                elseif c == "q" then result.quiet = true elseif c == "v" then result.verbose = true
                else error("Unknown short option: -" .. c, 0) end
            end
        else table.insert(result._, value) end
        i += 1
    end
    return result
end
return Args
