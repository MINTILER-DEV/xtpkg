-- SemVer 2.0 precedence; decimal strings avoid floating point precision loss.
local SemVer = {}
local function numeric(s) return s:match("^%d+$") ~= nil end
local function integer(s) return numeric(s) and (s == "0" or s:sub(1, 1) ~= "0") end
local function cmp(a, b)
    if #a ~= #b then return #a < #b and -1 or 1 end
    return a == b and 0 or (a < b and -1 or 1)
end
local function identifiers(s, prerelease)
    local parts = string.split(s, ".")
    for _, part in ipairs(parts) do
        if not part:match("^[0-9A-Za-z-]+$") or (prerelease and numeric(part) and not integer(part)) then error("Invalid semantic version identifier: " .. s, 0) end
    end
    return parts
end
function SemVer.parse(value)
    if type(value) ~= "string" or #value > 256 then error("Invalid semantic version: " .. tostring(value), 0) end
    local core, build = value:match("^(.-)%+(.+)$")
    core = core or value
    if build then identifiers(build, false) end
    local base, pre = core:match("^(.-)%-(.+)$")
    base = base or core
    local a, b, c = base:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a or not integer(a) or not integer(b) or not integer(c) then error("Invalid semantic version: " .. value, 0) end
    return { a, b, c, pre = pre and identifiers(pre, true) or nil, raw = value }
end
function SemVer.compare(a, b)
    a = type(a) == "string" and SemVer.parse(a) or a
    b = type(b) == "string" and SemVer.parse(b) or b
    for i = 1, 3 do local d = cmp(a[i], b[i]); if d ~= 0 then return d end end
    if not a.pre or not b.pre then return a.pre == b.pre and 0 or (a.pre and -1 or 1) end
    for i = 1, math.max(#a.pre, #b.pre) do
        local x, y = a.pre[i], b.pre[i]
        if not x or not y then return x == y and 0 or (x and 1 or -1) end
        if x ~= y then
            if numeric(x) and numeric(y) then return cmp(x, y) end
            if numeric(x) ~= numeric(y) then return numeric(x) and -1 or 1 end
            return x < y and -1 or 1
        end
    end
    return 0
end
local function increment(s)
    local out, carry = {}, 1
    for i = #s, 1, -1 do
        local n = tonumber(s:sub(i, i)) + carry
        table.insert(out, 1, tostring(n % 10)); carry = math.floor(n / 10)
    end
    if carry == 1 then table.insert(out, 1, "1") end
    return table.concat(out)
end
local function bound(a, b, c) return SemVer.parse(a .. "." .. b .. "." .. c) end
function SemVer.range(value)
    if type(value) ~= "string" or #value == 0 or #value > 512 then error("Invalid version range", 0) end
    local tests, prereleases = {}, {}
    local count = 0
    for token in value:gmatch("%S+") do
        count += 1
        if token == "*" or token == "x" or token == "X" then continue end
        local op, version = token:match("^([%^~<>=]+)(.+)$")
        op, version = op or "=", version or token
        local a, b = version:match("^(%d+)%.(%d+)%.[xX*]$")
        if a then
            if op ~= "=" or not integer(a) or not integer(b) then error("Invalid wildcard range: " .. token, 0) end
            table.insert(tests, { ">=", bound(a, b, "0") }); table.insert(tests, { "<", bound(a, increment(b), "0") })
        else
            local v = SemVer.parse(version)
            if v.pre then table.insert(prereleases, v) end
            if op == "^" or op == "~" then
                table.insert(tests, { ">=", v })
                local upper
                if op == "~" then upper = bound(v[1], increment(v[2]), "0")
                elseif v[1] ~= "0" then upper = bound(increment(v[1]), "0", "0")
                elseif v[2] ~= "0" then upper = bound("0", increment(v[2]), "0")
                else upper = bound("0", "0", increment(v[3])) end
                table.insert(tests, { "<", upper })
            elseif op == "=" or op == ">=" or op == "<=" or op == ">" or op == "<" then table.insert(tests, { op, v })
            else error("Unsupported range operator: " .. op, 0) end
        end
    end
    if count == 0 then error("Empty version range", 0) end
    return { tests = tests, prereleases = prereleases }
end
function SemVer.satisfies(version, range)
    local v = type(version) == "string" and SemVer.parse(version) or version
    local r = type(range) == "string" and SemVer.range(range) or range
    if v.pre then
        local permitted = false
        for _, p in ipairs(r.prereleases) do if v[1] == p[1] and v[2] == p[2] and v[3] == p[3] then permitted = true end end
        if not permitted then return false end
    end
    for _, t in ipairs(r.tests) do
        local c, op = SemVer.compare(v, t[2]), t[1]
        if (op == "=" and c ~= 0) or (op == ">=" and c < 0) or (op == "<=" and c > 0) or (op == ">" and c <= 0) or (op == "<" and c >= 0) then return false end
    end
    return true
end
function SemVer.sort(versions)
    table.sort(versions, function(a, b) local c = SemVer.compare(a, b); return c == 0 and a < b or c > 0 end)
    return versions
end
return SemVer
