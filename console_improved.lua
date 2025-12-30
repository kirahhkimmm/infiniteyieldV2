-- console_improved.lua
-- Lightweight, improved Developer Console replacement
-- Toggle with F9. Simple, responsive, and easier to extend.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local CoreGui = game:GetService('CoreGui')

local localPlayer = Players.LocalPlayer

-- Configuration
local cfg = {
    toggleKey = Enum.KeyCode.F9,
    width = 600,
    height = 400,
    background = Color3.fromRGB(20, 20, 20),
    textColor = Color3.fromRGB(230, 230, 230),
    transparency = 0.2,
    font = Enum.Font.SourceSans
}

-- Basic logger store
local messages = {}
local maxMessages = 500

local function addMessage(msg, color)
    table.insert(messages, 1, {text = tostring(msg), color = color or cfg.textColor})
    while #messages > maxMessages do table.remove(messages) end
end

-- Simple UI creation
local screen = Instance.new('ScreenGui')
screen.Name = 'ConsoleImproved'
screen.ResetOnSpawn = false
screen.Parent = CoreGui

local frame = Instance.new('Frame')
frame.Size = UDim2.new(0, cfg.width, 0, cfg.height)
frame.Position = UDim2.new(0.5, -cfg.width/2, 0.1, 0)
frame.BackgroundColor3 = cfg.background
frame.BackgroundTransparency = cfg.transparency
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screen

local title = Instance.new('TextLabel')
title.Size = UDim2.new(1, 0, 0, 26)
title.BackgroundTransparency = 1
title.Text = 'Console Improved (F9 to toggle)'
title.TextColor3 = cfg.textColor
title.Font = cfg.font
title.TextSize = 16
title.Parent = frame

local canvas = Instance.new('ScrollingFrame')
canvas.Size = UDim2.new(1, -10, 1, -36)
canvas.Position = UDim2.new(0, 5, 0, 30)
canvas.BackgroundTransparency = 1
canvas.BorderSizePixel = 0
canvas.CanvasSize = UDim2.new(0, 0, 1, 0)
canvas.ScrollBarThickness = 6
canvas.Parent = frame

local uiList = Instance.new('UIListLayout')
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.Padding = UDim.new(0, 4)
uiList.Parent = canvas

-- Top-right controls: Clear, Save, Search
local controlFrame = Instance.new('Frame')
controlFrame.Size = UDim2.new(0, 220, 0, 26)
controlFrame.Position = UDim2.new(1, -230, 0, 0)
controlFrame.BackgroundTransparency = 1
controlFrame.Parent = frame

local function makeButton(parent, text, xOffset)
    local b = Instance.new('TextButton')
    b.Size = UDim2.new(0, 64, 0, 20)
    b.Position = UDim2.new(0, xOffset, 0, 3)
    b.Text = text
    b.Font = cfg.font
    b.TextSize = 14
    b.BackgroundColor3 = Color3.fromRGB(40,40,40)
    b.TextColor3 = cfg.textColor
    b.BorderSizePixel = 0
    b.Parent = parent
    return b
end

local btnClear = makeButton(controlFrame, 'Clear', 0)
local btnSave = makeButton(controlFrame, 'Save', 70)

local searchBox = Instance.new('TextBox')
searchBox.Size = UDim2.new(0, 120, 0, 20)
searchBox.Position = UDim2.new(0, 140, 0, 3)
searchBox.Text = ''
searchBox.Font = cfg.font
searchBox.TextSize = 14
searchBox.PlaceholderText = 'search'
searchBox.BackgroundColor3 = Color3.fromRGB(30,30,30)
searchBox.TextColor3 = cfg.textColor
searchBox.BorderSizePixel = 0
searchBox.Parent = controlFrame

-- Small toggles panel for bypasses
local togglesFrame = Instance.new('Frame')
togglesFrame.Size = UDim2.new(0, 200, 0, 26)
togglesFrame.Position = UDim2.new(0, 8, 1, -32)
togglesFrame.BackgroundTransparency = 1
togglesFrame.Parent = frame

local togglesLabel = Instance.new('TextLabel')
togglesLabel.Size = UDim2.new(0, 80, 1, 0)
togglesLabel.Position = UDim2.new(0, 0, 0, 0)
togglesLabel.BackgroundTransparency = 1
togglesLabel.Text = 'Bypasses:'
togglesLabel.Font = cfg.font
togglesLabel.TextSize = 14
togglesLabel.TextColor3 = cfg.textColor
togglesLabel.Parent = togglesFrame

local function makeToggle(name, x)
    local b = Instance.new('TextButton')
    b.Size = UDim2.new(0, 60, 0, 20)
    b.Position = UDim2.new(0, x, 0, 3)
    b.Text = name
    b.Font = cfg.font
    b.TextSize = 12
    b.BackgroundColor3 = Color3.fromRGB(40,40,40)
    b.TextColor3 = cfg.textColor
    b.BorderSizePixel = 0
    b.Parent = togglesFrame
    return b
end

local toggleGC = makeToggle('GC', 80)
local toggleMem = makeToggle('Mem', 150)

-- Render messages into UI
local function refreshUI()
    -- limit children, reuse nodes if possible; apply search filter
    local filter = searchBox.Text and searchBox.Text:lower() or ''
    local shown = 0
    for i = 1, #messages do
        local data = messages[i]
        if filter == '' or tostring(data.text):lower():find(filter, 1, true) then
            shown = shown + 1
            local label = canvas:FindFirstChild('m'..shown)
            if not label then
                label = Instance.new('TextLabel')
                label.Name = 'm'..shown
                label.BackgroundTransparency = 1
                label.Size = UDim2.new(1, 0, 0, 18)
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.TextYAlignment = Enum.TextYAlignment.Top
                label.RichText = true
                label.Font = cfg.font
                label.TextSize = 14
                label.Parent = canvas
            end
            label.Text = tostring(data.text)
            label.TextColor3 = data.color
            label.LayoutOrder = shown
        end
    end
    -- remove extra UI nodes
    for _,v in pairs(canvas:GetChildren()) do
        if v:IsA('TextLabel') and tonumber(v.Name:sub(2)) and tonumber(v.Name:sub(2)) > shown then
            v:Destroy()
        end
    end
    -- update canvas size (simple approximation)
    canvas.CanvasSize = UDim2.new(0, 0, 0, math.max(shown * 22, canvas.AbsoluteSize.Y))
end

-- Capture prints and warn/errors
do
    local oldprint = print
    print = function(...)
        local t = {}
        for i=1, select('#', ...) do t[#t+1] = tostring(select(i, ...)) end
        local s = table.concat(t, '\t')
        addMessage(s, Color3.fromRGB(200,200,200))
        refreshUI()
        oldprint(...)
    end
end

-- Optional hooks for warn/error
do
    local oldwarn = warn
    warn = function(...)
        local t = {}
        for i=1, select('#', ...) do t[#t+1] = tostring(select(i, ...)) end
        local s = table.concat(t, '\t')
        addMessage('[WARN] '..s, Color3.fromRGB(255,200,0))
        refreshUI()
        oldwarn(...)
    end
    local olderror = error
    -- keep error unchanged but log when used via pcall wrappers if necessary
end

-- Toggle behavior
local visible = false
local function setVisible(v)
    visible = v
    frame.Visible = v
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == cfg.toggleKey then
        setVisible(not visible)
    end
end)

-- Button behaviors
btnClear.MouseButton1Click:Connect(function()
    Console.Clear()
end)

btnSave.MouseButton1Click:Connect(function()
    -- Save messages to file (workspace only)
    pcall(function()
        local f = io.open('console_log.txt', 'w')
        for i = #messages, 1, -1 do
            f:write(messages[i].text .. '\n')
        end
        f:close()
    end)
end)

searchBox:GetPropertyChangedSignal('Text'):Connect(function()
    refreshUI()
end)

-- Toggle behaviors (attempt to edit misc/bypasses_config.lua)
local function readConfig()
    local ok, cfgtbl = pcall(function()
        local f = io.open('misc/bypasses_config.lua','r')
        if not f then return nil end
        local s = f:read('*a')
        f:close()
        local chunk, err = load(s, 'bypass_cfg')
        if not chunk then return nil end
        return chunk()
    end)
    if ok and type(cfgtbl) == 'table' then return cfgtbl end
    return nil
end

local function writeConfig(tbl)
    pcall(function()
        local f = io.open('misc/bypasses_config.lua','w')
        if not f then return end
        f:write('return {\n')
        for k,v in pairs(tbl) do
            if type(v) == 'string' then
                f:write(string.format('\t%s = %q,\n', k, v))
            else
                f:write(string.format('\t%s = %s,\n', k, tostring(v)))
            end
        end
        f:write('}\n')
        f:close()
    end)
end

local function refreshToggles()
    local cfgtbl = readConfig()
    if cfgtbl then
        toggleGC.BackgroundColor3 = cfgtbl.gc_spoof and Color3.fromRGB(0,120,0) or Color3.fromRGB(80,80,80)
        toggleMem.BackgroundColor3 = cfgtbl.mem_spoof and Color3.fromRGB(0,120,0) or Color3.fromRGB(80,80,80)
    end
end

toggleGC.MouseButton1Click:Connect(function()
    local cfgtbl = readConfig() or {}
    cfgtbl.gc_spoof = not cfgtbl.gc_spoof
    writeConfig(cfgtbl)
    refreshToggles()
end)
toggleMem.MouseButton1Click:Connect(function()
    local cfgtbl = readConfig() or {}
    cfgtbl.mem_spoof = not cfgtbl.mem_spoof
    writeConfig(cfgtbl)
    refreshToggles()
end)

-- initialize toggles visual
refreshToggles()

-- Expose a simple API
local Console = {}
function Console.Log(msg)
    addMessage(tostring(msg))
    refreshUI()
end
function Console.Clear()
    messages = {}
    for _,v in pairs(canvas:GetChildren()) do if v:IsA('TextLabel') then v:Destroy() end end
    refreshUI()
end

-- Sample startup message
Console.Log('ConsoleImproved loaded. Toggle with F9.')

return Console
