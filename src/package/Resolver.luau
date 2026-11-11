local Util = require("./Util")
local Json = require("./Json")
local SemVer = require("./SemVer")
local Source = require("./Source")
local Cache = require("./Cache")
local Client = require("../registry/Client")
local Resolver = {}
function Resolver.resolve(directory, manifest, options)
    options = options or {}
    local client, localMemo, gitMemo = nil, {}, {}
    local attempts, lastFailure = 0, "No solution"
    local function registry()
        if not client then client = options.client or Client.new(options) end
        return client
    end
    local function special(name, requirement)
        local spec = requirement.spec
        if Util.pathSpec(spec) then
            local location = Util.localPath(requirement.base, spec)
            if options.offline or options.frozen then
                local p = options.previous and options.previous.packages[name]
                if p and p.source == "path:" .. location then Source.obtain(p, options); return p end
                error("Offline resolution needs a previously locked local snapshot for " .. name, 0)
            end
            if not localMemo[location] then
                local snapshot = Source.localSnapshot(location); local m = Source.validate(snapshot)
                local p = { name = m.package.name, version = m.package.version, source = "path:" .. location, revision = snapshot.integrity, integrity = snapshot.integrity, entry = m.package.entry, requirements = m.dependencies, dependencies = {}, base = location }
                Cache.write("packages", Cache.packageKey(p), snapshot); localMemo[location] = p
            end
            local p = localMemo[location]
            if p.name ~= name then error("Dependency identity mismatch: requested " .. name .. ", found " .. p.name, 0) end
            return p
        end
        if spec:sub(1, 4) == "git+" then
            if not options["allow-git"] then error("External Git dependencies require --allow-git (only immutable HTTPS commits are supported)", 0) end
            if not gitMemo[spec] then
                local url, revision = spec:match("^git%+(.+)#([0-9a-f]+)$")
                if options.offline then
                    local p = options.previous and options.previous.packages[name]
                    if p and p.source == "git+" .. url and p.revision == revision then Source.obtain(p, options); gitMemo[spec] = p
                    else error("Offline Git dependency is not locked/cached: " .. name, 0) end
                else
                    local snapshot = Source.gitSnapshot(url, revision, Cache.root(true), false); local m = Source.validate(snapshot)
                    gitMemo[spec] = { name = m.package.name, version = m.package.version, source = "git+" .. url, revision = revision, integrity = snapshot.integrity, entry = m.package.entry, requirements = m.dependencies, dependencies = {}, external = true }
                    Cache.write("packages", Cache.packageKey(gitMemo[spec]), snapshot)
                end
            end
            if gitMemo[spec].name ~= name then error("Git dependency identity mismatch: " .. name, 0) end
            return gitMemo[spec]
        end
        return nil
    end
    local function fits(p, requirements)
        for _, r in ipairs(requirements) do
            if Util.pathSpec(r.spec) then
                if p.source ~= "path:" .. Util.localPath(r.base, r.spec) then return false end
            elseif r.spec:sub(1, 4) == "git+" then
                if p.source .. "#" .. p.revision ~= r.spec then return false end
            elseif not SemVer.satisfies(p.version, r.spec) then return false end
        end
        return true
    end
    local function candidates(name, requirements)
        local selected
        for _, r in ipairs(requirements) do
            local p = special(name, r)
            if p then selected = p; break end
        end
        if selected then return fits(selected, requirements) and { selected } or {} end
        local data = registry():package(name); local versions = SemVer.sort(Util.keys(data.versions)); local list = {}
        for _, version in ipairs(versions) do
            local v = data.versions[version]
            local p = { name = name, version = version, source = "git+" .. v.source.url, revision = v.source.revision, integrity = v.integrity, entry = v.entry, requirements = v.dependencies, dependencies = {}, registry = registry().base }
            if fits(p, requirements) then table.insert(list, p) end
        end
        local previous = options.previous and options.previous.packages[name]
        if previous and options.update ~= true and options.update ~= name then
            for i, p in ipairs(list) do
                if p.version == previous.version and p.source == previous.source and p.revision == previous.revision then table.remove(list, i); table.insert(list, 1, p); break end
            end
        end
        return list
    end
    local function explain(name, requirements)
        local lines = { "Unable to resolve " .. name .. ": no version/source satisfies all requirements." }
        for _, r in ipairs(requirements) do table.insert(lines, "  " .. r.chain) end
        return table.concat(lines, "\n")
    end
    local function cycle(assigned)
        local visiting, done = {}, {}
        local function visit(name, chain, depth)
            if depth > 128 then return "Dependency depth exceeds 128" end
            if visiting[name] then return "Circular dependency: " .. chain .. " -> " .. name end
            if done[name] then return nil end
            visiting[name] = true
            for _, child in ipairs(Util.keys(assigned[name].requirements)) do
                local err = visit(child, chain .. " -> " .. name, depth + 1); if err then return err end
            end
            visiting[name] = nil; done[name] = true; return nil
        end
        for _, name in ipairs(Util.keys(assigned)) do local err = visit(name, manifest.package.name, 0); if err then return err end end
        return nil
    end
    local solve
    solve = function(assigned, constraints, depth)
        attempts += 1
        if attempts > 10000 or depth > 256 then error("Dependency resolution exceeded work limit (10000 attempts / 256 packages)", 0) end
        local pending
        for _, name in ipairs(Util.keys(constraints)) do
            if assigned[name] then if not fits(assigned[name], constraints[name]) then lastFailure = explain(name, constraints[name]); return nil end
            elseif not pending then pending = name end
        end
        if not pending then local err = cycle(assigned); if err then lastFailure = err; return nil end; return assigned end
        local ok, choices = pcall(candidates, pending, constraints[pending])
        if not ok then lastFailure = tostring(choices) .. "\n  " .. constraints[pending][1].chain; return nil end
        if #choices == 0 then lastFailure = explain(pending, constraints[pending]); return nil end
        for _, choice in ipairs(choices) do
            local nextAssigned, nextConstraints = table.clone(assigned), {}
            for name, rs in pairs(constraints) do nextConstraints[name] = table.clone(rs) end
            nextAssigned[pending] = table.clone(choice)
            for _, child in ipairs(Util.keys(choice.requirements)) do
                local spec = choice.requirements[child]
                nextConstraints[child] = nextConstraints[child] or {}
                if #nextConstraints[child] > 256 then error("Too many dependency constraints", 0) end
                table.insert(nextConstraints[child], { spec = spec, base = choice.base or directory, chain = constraints[pending][1].chain .. " -> " .. child .. "@" .. spec })
            end
            local solution = solve(nextAssigned, nextConstraints, depth + 1)
            if solution then return solution end
        end
        return nil
    end
    local constraints = {}
    for name, spec in pairs(manifest.dependencies) do constraints[name] = { { spec = spec, base = directory, chain = manifest.package.name .. " -> " .. name .. "@" .. spec } } end
    local solution = solve({}, constraints, 0)
    if not solution then error(lastFailure, 0) end
    for _, p in pairs(solution) do
        p.dependencies = {}
        for name in pairs(p.requirements) do p.dependencies[name] = solution[name].version end
        p.base = nil
    end
    return { lock_version = 2, roots = table.clone(manifest.dependencies), packages = solution }
end
function Resolver.isPathSpec(specification) return Util.pathSpec(specification) end
return Resolver
