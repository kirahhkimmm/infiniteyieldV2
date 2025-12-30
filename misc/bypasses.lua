-- Improved Bypasses (safer, configurable, bug fixes)
-- Place this file alongside `bypasses.lua`. It's a cleaner, modular version
-- of a few common detection bypasses for Roblox executor environments.

local config = {
    gc_spoof = true,
    gc_amplitude = 200,
    mem_spoof = true,
    mem_rand_range = 0.1,
    contentprovider_randomize = true,
    preload_hook = true,
    debug = false,
}

local function log(...)
    if config.debug then
        pcall(function() print('[Bypass]', ...) end)
    end
end

-- Safely wait for the game to load
task.spawn(function()
    repeat task.wait() until game and game:IsLoaded()
end)

local function safe_cloneref(obj)
    if type(cloneref) == 'function' then
        local ok, res = pcall(cloneref, obj)
        if ok then return res end
    end
    return obj
end

local has_hookfunction = type(hookfunction) == 'function'
local has_hookmetamethod = type(hookmetamethod) == 'function'
local has_newproxy = pcall(function() return (type(getrenv) == 'function' and type(getrenv().newproxy) == 'function') end)

-- GC spoof: make gcinfo()/collectgarbage('count') return a smoothed value
if config.gc_spoof then
    task.spawn(function()
        repeat task.wait() until game:IsLoaded()

        local amplitude = tonumber(config.gc_amplitude) or 200
        local floor = math.floor
        local cos, acos, pi = math.cos, math.acos, math.pi

        local maxima = 0
        while task.wait() do
            if (type(gcinfo) == 'function' and gcinfo() >= maxima) then
                maxima = gcinfo()
            else
                break
            end
        end

        task.wait(0.3)

        local base = (type(gcinfo) == 'function' and gcinfo() or 0) + amplitude
        local tickv = 0

        local function formula()
            return floor(base + ((acos(cos(pi * tickv)) / pi) * (amplitude * 2)) - amplitude)
        end

        if has_hookfunction and pcall(function() return getrenv().gcinfo end) then
            pcall(function()
                local old_gc = hookfunction(getrenv().gcinfo, function(...)
                    return formula()
                end)
                if pcall(function() return getrenv().collectgarbage end) then
                    local old_collectgarbage = hookfunction(getrenv().collectgarbage, function(arg, ...)
                        if arg == 'count' then
                            return formula()
                        end
                        return old_collectgarbage(arg, ...)
                    end)
                end
            end)

            game:GetService('RunService').Stepped:Connect(function()
                local f1 = (acos(cos(pi * tickv)) / pi) * (amplitude * 2) - amplitude
                local f2 = (acos(cos(pi * (tickv + 0.01))) / pi) * (amplitude * 2) - amplitude
                if f1 > f2 then
                    tickv = tickv + 0.07
                else
                    tickv = tickv + 0.01
                end
            end)

            log('gc spoof installed')
        end
    end)
end

-- Memory spoof: intercept Stats:GetTotalMemoryUsageMb and GetMemoryUsageMbForTag
if config.mem_spoof then
    task.spawn(function()
        repeat task.wait() until game:IsLoaded()

        local RunService = safe_cloneref(game:GetService('RunService'))
        local Stats = safe_cloneref(game:GetService('Stats'))
        local base_mem = 0
        pcall(function() base_mem = Stats:GetTotalMemoryUsageMb() end)

        local rnd = Random.new()
        local rand_offset = 0
        RunService.Stepped:Connect(function()
            rand_offset = rnd:NextNumber(-config.mem_rand_range, config.mem_rand_range)
        end)

        local function getreturn()
            return base_mem + rand_offset
        end

        if has_hookmetamethod and pcall(function() return true end) then
            pcall(function()
                local old = hookmetamethod(game, '__namecall', function(self, ...)
                    local method = getnamecallmethod()
                    if not checkcaller() and typeof(self) == 'Instance' and (method == 'GetTotalMemoryUsageMb' or method == 'getTotalMemoryUsageMb') and self.ClassName == 'Stats' then
                        return getreturn()
                    end
                    return old(self, ...)
                end)
            end)
        end

        -- Hook direct function access as fallback
        if pcall(function() return Stats.GetTotalMemoryUsageMb end) then
            pcall(function()
                if has_hookfunction then
                    local ok, oldf = pcall(function() return hookfunction(Stats.GetTotalMemoryUsageMb, function(self, ...) if not checkcaller() then return getreturn() end return oldf(self, ...) end) end)
                    -- ignore failure; best-effort only
                end
            end)
        end

        log('memory spoof installed')
    end)
end

-- ContentProvider PreloadAsync randomization (safer and fixed)
if config.contentprovider_randomize then
    task.spawn(function()
        repeat task.wait() until game:IsLoaded()

        local Content = safe_cloneref(game:GetService('ContentProvider'))
        local CoreGui = safe_cloneref(game:GetService('CoreGui'))

        local coreguiTable = {}
        local gameTable = {}

        -- collect images not in CoreGui
        for _,v in pairs(game:GetDescendants()) do
            if v:IsA('ImageLabel') or v:IsA('ImageButton') then
                if type(v.Image) == 'string' and not v.Image:find('rbxassetid://') and not v:IsDescendantOf(CoreGui) then
                    table.insert(gameTable, v.Image)
                elseif type(v.Image) == 'string' and v:IsDescendantOf(CoreGui) then
                    table.insert(coreguiTable, v.Image)
                end
            end
        end

        local function shuffle(t)
            for i = #t, 2, -1 do
                local j = math.random(i)
                t[i], t[j] = t[j], t[i]
            end
            return t
        end

        if has_hookmetamethod then
            pcall(function()
                local old = hookmetamethod(game, '__namecall', function(self, ...)
                    local method = getnamecallmethod()
                    local args = {...}
                    if not checkcaller() and typeof(self) == 'Instance' and (method == 'PreloadAsync' or method == 'preloadAsync') and args[1] and typeof(args[1]) == 'table' then
                        if args[1][1] == CoreGui then
                            return old(self, shuffle(table.clone(coreguiTable)), select(2, ...))
                        elseif args[1][1] == game then
                            return old(self, shuffle(table.clone(gameTable)), select(2, ...))
                        end
                    end
                    return old(self, ...)
                end)
            end)
        end

        log('contentprovider hooks installed')
    end)
end

-- Newproxy tracking: keep references to prevent some detectors from GC-ing proxies
do
    local proxies = {}
    if has_newproxy then
        local ok, old = pcall(function() return hookfunction(getrenv().newproxy, function(...) local p = old(...) table.insert(proxies, p) return p end) end)
        if ok then
            game:GetService('RunService').Stepped:Connect(function() for i=1,#proxies do local _ = proxies[i] end end)
            log('newproxy tracker installed')
        end
    end
end

return {
    config = config,
}
