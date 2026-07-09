--[[
    Ink Game - example script built on the Ney Hub library.

    This is the template for every future Ney Hub script:
    - one folder per game under Games/<GameName>/
    - same three loadstring lines to pull in the library + addons
    - same UI Settings tab wiring for ThemeManager/SaveManager

    Copy this file into a new Games/<GameName>/main.lua and swap the
    Main/Visuals/Misc sections for that game's actual logic.
]]

local REPO = "https://raw.githubusercontent.com/neyscript/NeyHub/main/"

local Library = loadstring(game:HttpGet(REPO .. "NeyHub/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(REPO .. "NeyHub/addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(REPO .. "NeyHub/addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

local Window = Library:CreateWindow({
    Title = "Ney Hub | Ink Game",
    Footer = "ney hub - ink game",
    NotifySide = "Right",
    ShowCustomCursor = true,
})

-- Second argument is a Lucide icon name (https://lucide.dev/) - without it
-- the tab still reserves the icon's space, just left blank.
local Tabs = {
    Main = Window:AddTab("Main", "gamepad-2"),
    ["Red Light"] = Window:AddTab("Red Light", "traffic-cone"),
    Dalgona = Window:AddTab("Dalgona", "cookie"),
    Visuals = Window:AddTab("Visuals", "eye"),
    Misc = Window:AddTab("Misc", "package"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

--// Main \\--
local MainGroup = Tabs.Main:AddLeftGroupbox("Ink Game")

MainGroup:AddToggle("AutoInk", {
    Text = "Auto Ink",
    Default = false,
    Tooltip = "Placeholder toggle - hook your Ink Game farm/loop logic here",
}):OnChanged(function(Value)
    -- TODO: start/stop your auto-ink loop based on Value
    print("AutoInk changed to:", Value)
end)

MainGroup:AddSlider("WalkSpeed", {
    Text = "Walkspeed",
    Default = 16,
    Min = 16,
    Max = 200,
    Rounding = 0,
    Callback = function(Value)
        local Character = game:GetService("Players").LocalPlayer.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        if Humanoid then
            Humanoid.WalkSpeed = Value
        end
    end,
})

MainGroup:AddButton("Reset Walkspeed", function()
    Options.WalkSpeed:SetValue(16)
end)

--// Red Light \\--
-- We don't have the real remote/value names for this round yet (no live
-- session to reverse engineer against), so instead of hardcoding a guess
-- this watches every signal a Squid-Game-style Red Light/Green Light round
-- realistically exposes to the client at once:
--   1) on-screen status text  (a TextLabel/TextButton showing "Red Light"/"Green Light")
--   2) sound cues             (a Sound instance named after the callout)
--   3) status value objects   (Bool/String/IntValue named like a light/round/doll state)
-- Whichever fires first wins. Turn on "Debug Logging" while actually inside
-- a round to see which source is reliable, then this can be trimmed down to
-- just that one strategy.
local RedLightGroup = Tabs["Red Light"]:AddLeftGroupbox("Light Monitor")

local LightStatusLabel = RedLightGroup:AddLabel("Status: Unknown")

local LightMonitor = {
    Active = false,
    Debug = false,
    Status = "Unknown",
    Connections = {}, -- [instance] = {RBXScriptConnection, ...}
}

local function MatchLightText(text)
    if typeof(text) ~= "string" or text == "" then
        return nil
    end

    local Lower = text:lower()

    if Lower:find("red%s*light") then
        return "Red"
    elseif Lower:find("green%s*light") then
        return "Green"
    end

    return nil
end

local function DebugLog(Source, Status, Instance)
    if not LightMonitor.Debug then return end
    print(("[Ney Hub | Red Light] %s -> %s (%s)"):format(Source, Status, Instance:GetFullName()))
end

local function SetLightStatus(Status, Source, Instance)
    if LightMonitor.Status == Status then return end

    LightMonitor.Status = Status
    LightStatusLabel:SetText("Status: " .. Status)
    DebugLog(Source, Status, Instance)
end

local function Track(Instance, Connection)
    local List = LightMonitor.Connections[Instance]
    if not List then
        List = {}
        LightMonitor.Connections[Instance] = List
    end
    table.insert(List, Connection)
end

local function WatchTextInstance(Instance)
    if LightMonitor.Connections[Instance] then return end

    local function Check()
        local Status = MatchLightText(Instance.Text)
        if Status then
            SetLightStatus(Status, "GUI Text", Instance)
        end
    end

    Track(Instance, Instance:GetPropertyChangedSignal("Text"):Connect(Check))
    Check()
end

local function WatchSoundInstance(Instance)
    if LightMonitor.Connections[Instance] then return end

    local function Check()
        local Status = MatchLightText(Instance.Name)
        if Status then
            SetLightStatus(Status, "Sound", Instance)
        end
    end

    Track(Instance, Instance.Played:Connect(Check))
end

local function WatchValueInstance(Instance)
    if LightMonitor.Connections[Instance] then return end

    local NameStatus = MatchLightText(Instance.Name)

    local function Check()
        if Instance:IsA("BoolValue") then
            if NameStatus and Instance.Value then
                SetLightStatus(NameStatus, Instance.ClassName .. " flag", Instance)
            end
        else
            local Status = MatchLightText(tostring(Instance.Value))
            if Status then
                SetLightStatus(Status, Instance.ClassName, Instance)
            end
        end
    end

    Track(Instance, Instance:GetPropertyChangedSignal("Value"):Connect(Check))
    Check()
end

local function TryWatch(Instance)
    if Instance:IsA("TextLabel") or Instance:IsA("TextButton") then
        WatchTextInstance(Instance)
    elseif Instance:IsA("Sound") then
        WatchSoundInstance(Instance)
    elseif Instance:IsA("BoolValue") or Instance:IsA("StringValue") or Instance:IsA("IntValue") then
        local Lower = Instance.Name:lower()
        if Lower:find("light") or Lower:find("round") or Lower:find("doll") then
            WatchValueInstance(Instance)
        end
    end
end

local function ScanRoot(Root)
    for _, Instance in ipairs(Root:GetDescendants()) do
        TryWatch(Instance)
    end
end

local function StartLightMonitor()
    if LightMonitor.Active then return end
    LightMonitor.Active = true
    LightMonitor.Status = "Unknown"
    LightStatusLabel:SetText("Status: Unknown")

    local Roots = { workspace, game:GetService("ReplicatedStorage") }

    local LocalPlayer = game:GetService("Players").LocalPlayer
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if PlayerGui then
        table.insert(Roots, PlayerGui)
    end

    for _, Root in ipairs(Roots) do
        ScanRoot(Root)
        Track(Root, Root.DescendantAdded:Connect(TryWatch))
    end
end

local function StopLightMonitor()
    if not LightMonitor.Active then return end
    LightMonitor.Active = false

    for _, Connections in pairs(LightMonitor.Connections) do
        for _, Connection in ipairs(Connections) do
            Connection:Disconnect()
        end
    end
    table.clear(LightMonitor.Connections)

    LightMonitor.Status = "Unknown"
    LightStatusLabel:SetText("Status: Unknown (monitor off)")
end

RedLightGroup:AddToggle("RedLightMonitor", {
    Text = "Monitor Light Status",
    Default = false,
    Tooltip = "Watches on-screen text, sound cues and status values to work out whether it's currently Red Light or Green Light",
}):OnChanged(function(Value)
    if Value then
        StartLightMonitor()
    else
        StopLightMonitor()
    end
end)

RedLightGroup:AddToggle("RedLightDebug", {
    Text = "Debug Logging",
    Default = false,
    Tooltip = "Prints every detection match to the console - enable while actually inside a Red Light round to see which source fires reliably",
}):OnChanged(function(Value)
    LightMonitor.Debug = Value
end)

Library:OnUnload(function()
    StopLightMonitor()
end)

--// Dalgona \\--
local DalgonaGroup = Tabs.Dalgona:AddLeftGroupbox("Dalgona")

DalgonaGroup:AddLabel("Coming soon - not implemented yet.", true)

--// Visuals \\--
local VisualsGroup = Tabs.Visuals:AddLeftGroupbox("Visuals")

VisualsGroup:AddToggle("PlayerESP", {
    Text = "Player ESP",
    Default = false,
    Tooltip = "Placeholder toggle - hook your ESP rendering here",
}):OnChanged(function(Value)
    -- TODO: create/destroy ESP highlights based on Value
    print("PlayerESP changed to:", Value)
end)

--// Misc \\--
local MiscGroup = Tabs.Misc:AddLeftGroupbox("Misc")

MiscGroup:AddDropdown("MiscOption", {
    Values = { "Option 1", "Option 2", "Option 3" },
    Default = 1,
    Text = "Example dropdown",
    Callback = function(Value)
        print("MiscOption changed to:", Value)
    end,
})

MiscGroup:AddLabel("Unload keybind"):AddKeyPicker("UnloadKeybind", {
    Default = "End",
    NoUI = true,
    Text = "Unload UI",
})

Library.ToggleKeybind = Options.UnloadKeybind

--// UI Settings (Theme + Config saving) \\--
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "UnloadKeybind" })

-- Themes are shared across every Ney Hub script, configs are per game
ThemeManager:SetFolder("NeyHub")
SaveManager:SetFolder("NeyHub/InkGame")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

Library:Notify("Ink Game (Ney Hub) loaded!", 3)
