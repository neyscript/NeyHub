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
local UserInputService = game:GetService("UserInputService")

local RedLightGroup = Tabs["Red Light"]:AddLeftGroupbox("Light Monitor")
local InspectorGroup = Tabs["Red Light"]:AddRightGroupbox("Element Inspector")

-- Returns Track(instance, connection), Clear(), Has(instance) - a tiny
-- connection bag shared by the light monitor and the inspector below so
-- neither has to hand-roll its own disconnect bookkeeping.
local function CreateConnectionTracker()
    local Store = {}

    local function Track(Instance, Connection)
        local List = Store[Instance]
        if not List then
            List = {}
            Store[Instance] = List
        end
        table.insert(List, Connection)
    end

    local function Has(Instance)
        return Store[Instance] ~= nil
    end

    local function Clear()
        for _, Connections in pairs(Store) do
            for _, Connection in ipairs(Connections) do
                Connection:Disconnect()
            end
        end
        table.clear(Store)
    end

    return Track, Clear, Has
end

local LightStatusLabel = RedLightGroup:AddLabel("Status: Unknown")

local LightMonitor = {
    Active = false,
    Debug = false,
    Status = "Unknown",
}

local TrackLight, ClearLightConnections, IsLightWatched = CreateConnectionTracker()

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

local function WatchTextInstance(Instance)
    if IsLightWatched(Instance) then return end

    local function Check()
        local Status = MatchLightText(Instance.Text)
        if Status then
            SetLightStatus(Status, "GUI Text", Instance)
        end
    end

    TrackLight(Instance, Instance:GetPropertyChangedSignal("Text"):Connect(Check))
    Check()
end

local function WatchSoundInstance(Instance)
    if IsLightWatched(Instance) then return end

    local function Check()
        local Status = MatchLightText(Instance.Name)
        if Status then
            SetLightStatus(Status, "Sound", Instance)
        end
    end

    TrackLight(Instance, Instance.Played:Connect(Check))
end

local function WatchValueInstance(Instance)
    if IsLightWatched(Instance) then return end

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

    TrackLight(Instance, Instance:GetPropertyChangedSignal("Value"):Connect(Check))
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
        TrackLight(Root, Root.DescendantAdded:Connect(TryWatch))
    end
end

local function StopLightMonitor()
    if not LightMonitor.Active then return end
    LightMonitor.Active = false

    ClearLightConnections()

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

-- Element Inspector: text/sound/values didn't reveal anything useful, but
-- there's a traffic-light icon changing color on screen - this lets you
-- tap it and grab its exact path + properties (and then watches those
-- properties live so you can see precisely what flips when the doll turns).
-- Mouse-hover + keybind doesn't work on mobile (Delta etc. have no mouse or
-- keyboard), so picking works by arming a one-shot tap: press the button,
-- then the very next tap/click anywhere on screen is used as the pick
-- position - this works the same on PC and on touch executors.
local TrackInspector, ClearInspectorConnections = CreateConnectionTracker()

local InspectorLog = InspectorGroup:AddLabel("Inspector: nothing picked yet", true)

InspectorGroup:AddLabel(
    "Press \"Arm Inspect\", then tap/click the traffic light icon on screen. Full paths print to the console; keep watching it while the doll flips to see exactly what changes.",
    true
)

local INSPECT_PROPERTIES = {
    "BackgroundColor3", "BackgroundTransparency",
    "ImageColor3", "ImageTransparency", "Image",
    "TextColor3", "Text",
    "Visible", "Transparency",
}

local function DescribeInstance(TargetInstance)
    local Parts = { TargetInstance.ClassName, TargetInstance:GetFullName() }

    for _, PropName in ipairs(INSPECT_PROPERTIES) do
        local Ok, Value = pcall(function() return TargetInstance[PropName] end)
        if Ok and Value ~= nil then
            table.insert(Parts, PropName .. "=" .. tostring(Value))
        end
    end

    return table.concat(Parts, " | ")
end

local function WatchInspectedProperties(TargetInstance)
    for _, PropName in ipairs(INSPECT_PROPERTIES) do
        local Ok, Signal = pcall(function()
            return TargetInstance:GetPropertyChangedSignal(PropName)
        end)

        if Ok and Signal then
            TrackInspector(TargetInstance, Signal:Connect(function()
                local ValueOk, Value = pcall(function() return TargetInstance[PropName] end)
                if not ValueOk then return end

                local Line = ("%s.%s -> %s"):format(TargetInstance:GetFullName(), PropName, tostring(Value))
                print("[Ney Hub | Inspector] " .. Line)
                InspectorLog:SetText(Line)
            end))
        end
    end
end

local InspectorHighlightGui = nil

local function GetInspectorHighlightGui(PlayerGui)
    if InspectorHighlightGui and InspectorHighlightGui.Parent then
        return InspectorHighlightGui
    end

    InspectorHighlightGui = Instance.new("ScreenGui")
    InspectorHighlightGui.Name = "NeyHubInspectorHighlight"
    InspectorHighlightGui.ResetOnSpawn = false
    InspectorHighlightGui.IgnoreGuiInset = false
    InspectorHighlightGui.DisplayOrder = 2147483647
    InspectorHighlightGui.Parent = PlayerGui

    return InspectorHighlightGui
end

local function FlashHighlight(PlayerGui, TargetInstance)
    local PosOk, AbsolutePosition = pcall(function() return TargetInstance.AbsolutePosition end)
    local SizeOk, AbsoluteSize = pcall(function() return TargetInstance.AbsoluteSize end)
    if not (PosOk and SizeOk) then return end

    local Box = Instance.new("Frame")
    Box.BackgroundTransparency = 1
    Box.BorderSizePixel = 0
    Box.Position = UDim2.fromOffset(AbsolutePosition.X, AbsolutePosition.Y)
    Box.Size = UDim2.fromOffset(AbsoluteSize.X, AbsoluteSize.Y)
    Box.ZIndex = 10000
    Box.Parent = GetInspectorHighlightGui(PlayerGui)

    local Stroke = Instance.new("UIStroke")
    Stroke.Thickness = 2
    Stroke.Color = Color3.fromRGB(0, 200, 255)
    Stroke.Parent = Box

    task.delay(1.5, function()
        Box:Destroy()
    end)
end

local function InspectElementAtPosition(ScreenPosition)
    local LocalPlayer = game:GetService("Players").LocalPlayer
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return end

    local Ok, Hits = pcall(function()
        return PlayerGui:GetGuiObjectsAtPosition(ScreenPosition.X, ScreenPosition.Y)
    end)

    if not Ok or not Hits or #Hits == 0 then
        InspectorLog:SetText("Inspector: nothing under that tap - try again")
        return
    end

    ClearInspectorConnections()

    print(("[Ney Hub | Inspector] --- %d element(s) at tap position (top -> bottom) ---"):format(#Hits))
    for Index, HitInstance in ipairs(Hits) do
        print(("[Ney Hub | Inspector] #%d %s"):format(Index, DescribeInstance(HitInstance)))
        WatchInspectedProperties(HitInstance)
        FlashHighlight(PlayerGui, HitInstance)
    end

    InspectorLog:SetText(("Picked %d element(s) - see console, now watching for live changes"):format(#Hits))
end

local InspectArmed = false
local InspectArmConnection = nil

local function ArmInspectPick()
    if InspectArmed then return end
    InspectArmed = true
    InspectorLog:SetText("Inspector: armed - tap/click the traffic light on screen")

    InspectArmConnection = UserInputService.InputBegan:Connect(function(Input, GameProcessedEvent)
        if GameProcessedEvent then return end

        local InputType = Input.UserInputType
        if InputType ~= Enum.UserInputType.Touch and InputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        InspectArmConnection:Disconnect()
        InspectArmConnection = nil
        InspectArmed = false

        InspectElementAtPosition(Input.Position)
    end)
end

InspectorGroup:AddButton("Arm Inspect (tap target next)", function()
    ArmInspectPick()
end)

InspectorGroup:AddButton("Clear Watches", function()
    ClearInspectorConnections()
    InspectorLog:SetText("Inspector: watches cleared")
end)

Library:OnUnload(function()
    StopLightMonitor()
    ClearInspectorConnections()
    if InspectArmConnection then
        InspectArmConnection:Disconnect()
    end
    if InspectorHighlightGui then
        InspectorHighlightGui:Destroy()
    end
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
