local fs = require("system/fs")
local path = require("system/path")
local hash = require("crypto/hash")
local uuid = require("crypto/uuid")
local Util = {}

function Util.keys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

function Util.name(name)
    if type(name) ~= "string" or #name > 120 then return false end
    local parts = string.split(name, "/")
    if #parts > 2 then return false end
    for _, part in ipairs(parts) do
        if not part:match("^[a-z0-9][a-z0-9_-]*$") or #part > 60 then return false end
        local stem = part:lower()
        if stem == "con" or stem == "prn" or stem == "aux" or stem == "nul" or stem:match("^com%d$") or stem:match("^lpt%d$") then return false end
    end
    return true
end

function Util.relative(value)
    if type(value) ~= "string" or #value == 0 or #value > 240 or value:find("[\\:%c]") or value:sub(1, 1) == "/" then return false end
    -- Portable ASCII names avoid Unicode case/normalization collisions and
    -- Windows short-name aliases (e.g. LONGFI~1) when materializing a tree.
    if not value:match("^[A-Za-z0-9_.+@ /()%-]+$") then return false end
    for _, part in ipairs(string.split(value, "/")) do
        if part == "" or part == "." or part == ".." or part:find('[<>"|?*]') or part:match("[ .]$") then return false end
        local stem = part:lower():match("^([^.]+)") or ""
        if stem == "con" or stem == "prn" or stem == "aux" or stem == "nul" or stem:match("^com%d$") or stem:match("^lpt%d$") then return false end
    end
    return true
end

function Util.absolute(base, value)
    return path.isAbsolute(value) and path.normalize(value) or path.join(base, value)
end

function Util.mkdir(p) if not fs.exists(p) then fs.mkdir(p, true):await() end end
function Util.remove(p) if fs.exists(p) then fs.remove(p, true):await() end end
function Util.id() return uuid.v4() end
function Util.sha(value) return hash.sha256(value) end
function Util.revision(value) return type(value) == "string" and #value == 40 and value:match("^[0-9a-f]+$") ~= nil end
function Util.checksum(value) return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil end
function Util.pathSpec(s)
    if type(s) ~= "string" then return false end
    local normalized = s:gsub("\\", "/")
    return normalized:sub(1, 5) == "path:" or normalized:sub(1, 2) == "./" or normalized:sub(1, 3) == "../" or path.isAbsolute(s)
end
function Util.localPath(base, s) return Util.absolute(base, s:sub(1, 5) == "path:" and s:sub(6) or s) end

-- Credentials and non-HTTPS network transports are deliberately not accepted.
function Util.url(value)
    if type(value) ~= "string" or #value > 2048 or value:find("[%s%c@?#\\]") then return false end
    return value:match("^https://[%w.-]+/[%w%._~/-]+$") ~= nil
end

function Util.git(arguments, cwd)
    local args = { "-c", "core.hooksPath=", "-c", "protocol.file.allow=always", "-c", "protocol.ext.allow=never" }
    for _, arg in ipairs(arguments) do table.insert(args, arg) end
    local r = process.exec("git", args, { cwd = cwd, env = { GIT_TERMINAL_PROMPT = "0", GIT_OPTIONAL_LOCKS = "0", GIT_CONFIG_NOSYSTEM = "1", GIT_CONFIG_GLOBAL = process.getenv("COMSPEC") and "NUL" or "/dev/null" } })
    if r.code ~= 0 then error("Git operation failed (" .. tostring(arguments[1]) .. "). Check the source URL, revision, and Git installation.", 0) end
    return r.stdout
end

-- fs.stat follows links in LuauXTX. Use OS metadata to reject links/reparse
-- points before filesystem traversal, including links in existing ancestors.
function Util.noLinks(location)
    local r
    if process.getenv("COMSPEC") then
        r = process.exec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; $p=[IO.Path]::GetFullPath($env:XTPKG_CHECK_PATH); while ($p) { if (Test-Path -LiteralPath $p) { $i=Get-Item -Force -LiteralPath $p; if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { exit 2 } }; $p=[IO.Path]::GetDirectoryName($p) }" }, { env = { XTPKG_CHECK_PATH = location } })
    else
        r = process.exec("sh", { "-c", 'p="$XTPKG_CHECK_PATH"; while [ "$p" != / ] && [ "$p" != . ]; do [ ! -L "$p" ] || exit 2; p=$(dirname -- "$p") || exit 3; done' }, { env = { XTPKG_CHECK_PATH = location } })
    end
    if r.code ~= 0 then error("Unsafe symbolic link/reparse point or inaccessible path: " .. location, 0) end
end

function Util.noLinksTree(location)
    Util.noLinks(location)
    if not fs.exists(location) then return end
    local r
    if process.getenv("COMSPEC") then
        r = process.exec("powershell.exe", { "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; $q=New-Object 'Collections.Generic.Queue[string]'; $q.Enqueue($env:XTPKG_CHECK_PATH); $n=0; while($q.Count) { foreach($i in Get-ChildItem -LiteralPath $q.Dequeue() -Force) { if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { exit 2 }; $n++; if($n -gt 100000) { exit 3 }; if($i.PSIsContainer) { $q.Enqueue($i.FullName) } } }" }, { env = { XTPKG_CHECK_PATH = location } })
    else
        r = process.exec("find", { "-P", location, "-type", "l", "-print" })
    end
    if r.code ~= 0 or r.stdout ~= "" then error("Unsafe links, excessive entries, or inaccessible tree: " .. location, 0) end
end

return Util
