-- Improved Bypasses (safer, configurable, bug fixes)
-- Place this file alongside `bypasses.lua`. It's a cleaner, modular version
-- of a few common detection bypasses for Roblox executor environments.

-- Default config; can be overridden by `misc/bypasses_config.lua` on disk.
local config = {
    gc_spoof = true,
    gc_amplitude = 200,
    mem_spoof = true,
    mem_rand_range = 0.1,
    contentprovider_randomize = true,
    preload_hook = true,
    debug = false,
}

-- Try to load external config file (development/workspace only)
do
    local ok, ext = pcall(function()
        local f = io.open('misc/bypasses_config.lua', 'r')
        if not f then return nil end
        local s = f:read('*a')
        f:close()
        -- We only expect the file to `return { ... }` so prepend 'return ' if needed is not necessary
        local chunk, err = load(s, 'bypasses_config')
        if not chunk then return nil end
        return chunk()
    end)
    if ok and type(ext) == 'table' then
        for k,v in pairs(ext) do config[k] = v end
    end
end

local function log(...)
    if config.debug then
        pcall(function() print('[Bypass]', ...) end)
    end
end

-- Safely wait for the game to load
task.spawn(function()
    repeat task.wait() until game and game:IsLoaded()
end)

-- GC spoof: make gcinfo()/collectgarbage('count') return a smoothed value
if config.gc_spoof then
    task.spawn(function()
        repeat task.wait() until game:IsLoaded()

        local amplitude = tonumber(config.gc_amplitude) or 200
        local floor = math.floor
        local cos, acos, pi = math.cos, math.acos, math.pi

        local maxima = 0
        while task.wait() do
            if gcinfo() >= maxima then
                maxima = gcinfo()
            else
                break
            end
        end

        task.wait(0.3)

        local base = gcinfo() + amplitude
        local tickv = 0

        local function formula()
            return floor(base + ((acos(cos(pi * tickv)) / pi) * (amplitude * 2)) - amplitude)
        end

        if type(getrenv) == 'function' and type(getrenv().gcinfo) == 'function' then
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

        local RunService = cloneref(game:GetService('RunService'))
        local Stats = cloneref(game:GetService('Stats'))
        local base_mem = 0
        if pcall(function() base_mem = Stats:GetTotalMemoryUsageMb() end) then
            base_mem = base_mem
        else
            base_mem = 0
        end

        local rand = 0
        RunService.Stepped:Connect(function()
            local random = Random.new()
            rand = random:NextNumber(-config.mem_rand_range, config.mem_rand_range)
        end)

        local function getreturn()
            return base_mem + rand
        end

        if hookmetamethod then
            local old = hookmetamethod(game, '__namecall', function(self, ...)
                local method = getnamecallmethod()
                if not checkcaller() and typeof(self) == 'Instance' and (method == 'GetTotalMemoryUsageMb' or method == 'getTotalMemoryUsageMb') and self.ClassName == 'Stats' then
                    return getreturn()
                end
                return old(self, ...)
            end)
        end

        -- Hook direct function access as fallback
        if pcall(function() return Stats.GetTotalMemoryUsageMb end) then
            pcall(function()
                local oldf = hookfunction(Stats.GetTotalMemoryUsageMb, function(self, ...)
                    if not checkcaller() then
                        return getreturn()
                    end
                    return oldf(self, ...)
                end)
            end)
        end

        log('memory spoof installed')
    end)
end

-- ContentProvider PreloadAsync randomization (safer and fixed)
if config.contentprovider_randomize then
    task.spawn(function()
        repeat task.wait() until game:IsLoaded()

        local Content = cloneref(game:GetService('ContentProvider'))
        local CoreGui = cloneref(game:GetService('CoreGui'))

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

        if hookmetamethod then
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
        end

        log('contentprovider hooks installed')
    end)
end

-- Newproxy tracking: keep references to prevent some detectors from GC-ing proxies
do
    local proxies = {}
    if type(getrenv) == 'function' and type(getrenv().newproxy) == 'function' then
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
