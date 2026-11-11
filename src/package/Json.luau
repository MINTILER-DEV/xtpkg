-- Strict, bounded JSON for untrusted registry/cache input. Runtime serde/json
-- currently accepts duplicate keys and does not decode Unicode escapes.
local Json = {}
local null = table.freeze({})
Json.null = null
function Json.encode(v)
    if v == null then return "null" end
    local t = type(v)
    if t == "string" then
        return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
            if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
            return string.format("\\u%04x", string.byte(c))
        end) .. '"'
    elseif t == "number" then assert(v == v and math.abs(v) < math.huge, "Non-finite JSON number"); return tostring(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "table" then
        local keys, out = {}, {}
        for k in pairs(v) do assert(type(k) == "string", "JSON object keys must be strings"); table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do table.insert(out, Json.encode(k) .. ":" .. Json.encode(v[k])) end
        return "{" .. table.concat(out, ",") .. "}"
    end
    error("Unsupported JSON value: " .. t, 0)
end
function Json.decode(s, limit)
    assert(type(s) == "string" and #s <= (limit or 2 * 1024 * 1024), "JSON exceeds size limit")
    local i, nodes = 1, 0
    local function fail() error("Malformed or excessive JSON at byte " .. i, 0) end
    local function space() while s:sub(i, i):match("[ \t\r\n]") do i += 1 end end
    local function hex4()
        local h = s:sub(i, i + 3)
        if #h ~= 4 or not h:match("^%x+$") then fail() end
        i += 4; return tonumber(h, 16)
    end
    local function str()
        if s:sub(i, i) ~= '"' then fail() end
        i += 1; local out = {}
        while i <= #s do
            local c = s:sub(i, i); i += 1
            if c == '"' then return table.concat(out) end
            if c == "\\" then
                c = s:sub(i, i); i += 1
                local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if c == "u" then
                    local cp = hex4()
                    if cp >= 0xd800 and cp <= 0xdbff then
                        if s:sub(i, i + 1) ~= "\\u" then fail() end
                        i += 2; local low = hex4()
                        if low < 0xdc00 or low > 0xdfff then fail() end
                        cp = 0x10000 + (cp - 0xd800) * 1024 + low - 0xdc00
                    elseif cp >= 0xdc00 and cp <= 0xdfff then fail() end
                    c = utf8.char(cp)
                else c = escapes[c]; if c == nil then fail() end end
            elseif string.byte(c) < 32 then fail() end
            table.insert(out, c)
        end
        fail()
    end
    local parse
    parse = function(depth)
        nodes += 1
        if depth > 40 or nodes > 100000 then fail() end
        space(); local c = s:sub(i, i)
        if c == '"' then return str() end
        if c == "{" or c == "[" then
            local object = c == "{"; local close = object and "}" or "]"
            local result, seen = {}, {}; i += 1; space()
            if s:sub(i, i) == close then i += 1; return result end
            while true do
                space(); local key
                if object then key = str(); if seen[key] then fail() end; seen[key] = true; space(); if s:sub(i, i) ~= ":" then fail() end; i += 1 end
                local v = parse(depth + 1)
                if object then result[key] = v else table.insert(result, v) end
                space(); local nextChar = s:sub(i, i); i += 1
                if nextChar == close then return result end
                if nextChar ~= "," then fail() end
            end
        end
        for literal, v in pairs({ ["true"] = true, ["false"] = false, ["null"] = null }) do
            if s:sub(i, i + #literal - 1) == literal then i += #literal; return v end
        end
        local token = s:sub(i):match("^[^,%]%}%s]+")
        if not token then fail() end
        local mantissa, exponent = token:match("^(.-)[eE]([+-]?%d+)$")
        mantissa = mantissa or token
        local whole, fraction = mantissa:match("^(%-?%d+)%.(%d+)$")
        whole = whole or mantissa
        local digits = whole:gsub("^-", "")
        if not whole:match("^%-?%d+$") or (#digits > 1 and digits:sub(1, 1) == "0") then fail() end
        local n = tonumber(token)
        if not n or n ~= n or math.abs(n) == math.huge then fail() end
        -- Ensure malformed fractional/exponent syntax was not accepted by tonumber.
        if not fraction and mantissa:find("%.") then fail() end
        if not exponent and token:find("[eE]") then fail() end
        i += #token; return n
    end
    local result = parse(0); space(); if i <= #s then fail() end
    return result
end
return Json
