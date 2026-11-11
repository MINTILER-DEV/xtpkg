-- A strict scalar TOML reader for XTPKG's three supported sections. Other
-- sections are preserved byte-for-byte when dependency declarations change.
local Json = require("./Json")
local Toml = {}
function Toml.quote(s) return Json.encode(s) end
local function uncomment(line)
    local quote, escaped = nil, false
    for i = 1, #line do
        local c = line:sub(i, i)
        if quote then
            if quote == '"' and c == "\\" and not escaped then escaped = true
            elseif c == quote and not escaped then quote = nil
            else escaped = false end
        elseif c == '"' or c == "'" then quote = c
        elseif c == "#" then return line:sub(1, i - 1) end
    end
    return line
end
local function scalar(s)
    s = s:match("^%s*(.-)%s*$")
    if s:sub(1, 1) == '"' then
        local value = Json.decode(s, 65536)
        assert(type(value) == "string", "Expected TOML string"); return value
    end
    if s:sub(1, 1) == "'" and s:sub(-1) == "'" and not s:sub(2, -2):find("'", 1, true) then return s:sub(2, -2) end
    if s == "true" then return true elseif s == "false" then return false end
    if s:match("^%-?%d+$") then return tonumber(s) end
    error("Unsupported or malformed TOML value: " .. s .. ". Use quoted strings in package, dependencies, and scripts.", 0)
end
function Toml.decode(text)
    assert(#text <= 1024 * 1024, "xtpkg.toml exceeds size limit")
    local result, section, seen = {}, nil, {}
    for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
        local line = uncomment(raw):match("^%s*(.-)%s*$")
        if line == "" then continue end
        if line:sub(1, 1) == "[" then
            section = line:match("^%[([%w_.-]+)%]$")
            if not section then error("Unsupported or malformed TOML table header: " .. line, 0) end
            if seen[section] then error("Duplicate TOML table: " .. section, 0) end
            seen[section] = true
            if section == "package" or section == "dependencies" or section == "scripts" then result[section] = {} end
        elseif section == "package" or section == "dependencies" or section == "scripts" then
            local k, v = line:match('^("[^"\r\n]+")%s*=%s*(.+)$')
            if not k then k, v = line:match("^('[^'\r\n]+')%s*=%s*(.+)$") end
            if not k then k, v = line:match("^([%w_-]+)%s*=%s*(.+)$") end
            if not k then error("Malformed TOML declaration: " .. line, 0) end
            if k:sub(1, 1) == '"' or k:sub(1, 1) == "'" then k = scalar(k) end
            if result[section][k] ~= nil then error("Duplicate TOML key: " .. k, 0) end
            result[section][k] = scalar(v)
        elseif not section then error("Manifest values must be inside a table", 0) end
    end
    return result
end
function Toml.dependencies(text, dependencies)
    local lines, inside, found = {}, false, false
    local function emit()
        local keys = {}; for k in pairs(dependencies) do table.insert(keys, k) end; table.sort(keys)
        for _, k in ipairs(keys) do table.insert(lines, Toml.quote(k) .. " = " .. Toml.quote(dependencies[k])) end
    end
    for raw in (text:gsub("\r\n", "\n"):gsub("\n$", "") .. "\n"):gmatch("(.-)\n") do
        local header = uncomment(raw):match("^%s*(%[.-%])%s*$")
        if header then
            if inside then emit(); inside = false end
            if header == "[dependencies]" then inside = true; found = true end
        end
        if not inside or header then table.insert(lines, raw)
        elseif raw:match("^%s*#") or raw:match("^%s*$") then table.insert(lines, raw) end
    end
    if inside then emit() end
    if not found then table.insert(lines, ""); table.insert(lines, "[dependencies]"); emit() end
    return table.concat(lines, "\n") .. "\n"
end
return Toml
