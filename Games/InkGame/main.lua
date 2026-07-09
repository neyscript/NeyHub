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
-- Confirmed via the Element Inspector below: the traffic-light HUD icon is
-- an ImageLabel named "TrafficLightEmpty" under PlayerGui, and its `.Image`
-- property swaps between two rbxassetids depending on the round state.
-- We don't hardcode which id means Red and which means Green here (that's
-- exactly the kind of thing that's easy to get backwards from a screenshot,
-- and getting it backwards would auto-walk on red instead of freezing) -
-- calibrate it live instead with the "Set Current As Red/Green Light"
-- buttons while actually looking at the doll.
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = game:GetService("Players").LocalPlayer

local RedLightGroup = Tabs["Red Light"]:AddLeftGroupbox("Light Monitor")
local AutoPassGroup = Tabs["Red Light"]:AddLeftGroupbox("Auto Pass")
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

-- Fill these in with the values printed by the "Set Current As ..." buttons
-- below once calibrated, so the script works without a manual calibration
-- step every time. Live calibration always overrides these at runtime.
local DEFAULT_RED_IMAGE_ID = nil
local DEFAULT_GREEN_IMAGE_ID = nil
local DEFAULT_FINISH_POSITION = nil -- Vector3.new(x, y, z), from "Save Finish Position"

local Calibration = {
    RedImageId = DEFAULT_RED_IMAGE_ID,
    GreenImageId = DEFAULT_GREEN_IMAGE_ID,
}

local TrackLight, ClearLightConnections = CreateConnectionTracker()

local LightStatusListeners = {}
local function OnLightStatusChanged(Callback)
    table.insert(LightStatusListeners, Callback)
end

local function SetLightStatus(Status, Source)
    if LightMonitor.Status == Status then return end

    LightMonitor.Status = Status
    LightStatusLabel:SetText("Status: " .. Status)

    if LightMonitor.Debug then
        print(("[Ney Hub | Red Light] %s -> %s"):format(Source, Status))
    end

    for _, Callback in ipairs(LightStatusListeners) do
        task.spawn(Callback, Status)
    end
end

local TrafficLightInstance = nil
local TrafficLightConnection = nil

local function HandleTrafficLightImageChanged()
    local Image = TrafficLightInstance.Image

    if LightMonitor.Debug then
        print(("[Ney Hub | Red Light] TrafficLightEmpty.Image -> %s"):format(tostring(Image)))
    end

    if Calibration.RedImageId and Image == Calibration.RedImageId then
        SetLightStatus("Red", "TrafficLightEmpty.Image")
    elseif Calibration.GreenImageId and Image == Calibration.GreenImageId then
        SetLightStatus("Green", "TrafficLightEmpty.Image")
    end
end

local function BindTrafficLight(Instance)
    if TrafficLightInstance == Instance then return end

    if TrafficLightConnection then
        TrafficLightConnection:Disconnect()
    end

    TrafficLightInstance = Instance
    TrafficLightConnection = Instance:GetPropertyChangedSignal("Image"):Connect(HandleTrafficLightImageChanged)
    HandleTrafficLightImageChanged()
end

local function TryBindTrafficLight(Instance)
    if Instance.Name == "TrafficLightEmpty" and (Instance:IsA("ImageLabel") or Instance:IsA("ImageButton")) then
        BindTrafficLight(Instance)
    end
end

local function StartLightMonitor()
    if LightMonitor.Active then return end
    LightMonitor.Active = true
    LightMonitor.Status = "Unknown"
    LightStatusLabel:SetText("Status: Unknown")

    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return end

    for _, Instance in ipairs(PlayerGui:GetDescendants()) do
        TryBindTrafficLight(Instance)
    end
    TrackLight(PlayerGui, PlayerGui.DescendantAdded:Connect(TryBindTrafficLight))
end

local function StopLightMonitor()
    if not LightMonitor.Active then return end
    LightMonitor.Active = false

    ClearLightConnections()

    if TrafficLightConnection then
        TrafficLightConnection:Disconnect()
        TrafficLightConnection = nil
    end
    TrafficLightInstance = nil

    LightMonitor.Status = "Unknown"
    LightStatusLabel:SetText("Status: Unknown (monitor off)")
end

RedLightGroup:AddToggle("RedLightMonitor", {
    Text = "Monitor Light Status",
    Default = false,
    Tooltip = "Watches the TrafficLightEmpty icon's Image property to work out whether it's currently Red Light or Green Light",
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
    Tooltip = "Prints every raw Image change and status flip to the console",
}):OnChanged(function(Value)
    LightMonitor.Debug = Value
end)

--// Auto Pass \\--
-- Freezes movement on Red, walks to the saved finish position on Green.
-- With no finish position saved it still just freezes on red (auto stop)
-- and leaves movement to you on green.
local CalibrationLabel = AutoPassGroup:AddLabel("Calibration - Red: not set | Green: not set")
local FinishLabel = AutoPassGroup:AddLabel("Finish position: not set")

local FinishPosition = DEFAULT_FINISH_POSITION
if FinishPosition then
    FinishLabel:SetText(("Finish position: %.1f, %.1f, %.1f"):format(FinishPosition.X, FinishPosition.Y, FinishPosition.Z))
end

local function RefreshCalibrationLabel()
    CalibrationLabel:SetText(("Calibration - Red: %s | Green: %s"):format(
        Calibration.RedImageId and "set" or "not set",
        Calibration.GreenImageId and "set" or "not set"
    ))
end

local function CalibrateLight(Which, Label)
    if not TrafficLightInstance then
        Library:Notify("Traffic light not found yet - turn on Monitor Light Status inside a Red Light round first", 4)
        return
    end

    Calibration[Which] = TrafficLightInstance.Image
    RefreshCalibrationLabel()

    print(("[Ney Hub | Red Light] Calibrated %s light = %s"):format(Label, Calibration[Which]))
    Library:Notify("Calibrated " .. Label .. " light", 2)
end

AutoPassGroup:AddButton("Set Current As Red Light", function()
    CalibrateLight("RedImageId", "Red")
end)

AutoPassGroup:AddButton("Set Current As Green Light", function()
    CalibrateLight("GreenImageId", "Green")
end)

AutoPassGroup:AddButton("Save Finish Position", function()
    local Character = LocalPlayer.Character
    local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    if not HumanoidRootPart then
        Library:Notify("No character found - can't save a position", 3)
        return
    end

    FinishPosition = HumanoidRootPart.Position
    FinishLabel:SetText(("Finish position: %.1f, %.1f, %.1f"):format(FinishPosition.X, FinishPosition.Y, FinishPosition.Z))

    print(("[Ney Hub | Red Light] Finish position saved: Vector3.new(%.3f, %.3f, %.3f)"):format(FinishPosition.X, FinishPosition.Y, FinishPosition.Z))
    Library:Notify("Finish position saved - see console for exact coords", 3)
end)

local function FreezeMovement()
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    if not (Humanoid and HumanoidRootPart) then return end

    Humanoid.WalkSpeed = 0
    Humanoid:MoveTo(HumanoidRootPart.Position)
end

local function ResumeMovement()
    local Character = LocalPlayer.Character
    local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return end

    Humanoid.WalkSpeed = (Options.WalkSpeed and Options.WalkSpeed.Value) or 16

    if FinishPosition then
        Humanoid:MoveTo(FinishPosition)
    end
end

local AutoPassActive = false

OnLightStatusChanged(function(Status)
    if not AutoPassActive then return end

    if Status == "Red" then
        FreezeMovement()
    elseif Status == "Green" then
        ResumeMovement()
    end
end)

AutoPassGroup:AddToggle("AutoPass", {
    Text = "Auto Pass",
    Default = false,
    Tooltip = "Freezes on Red, auto-walks to the saved finish position on Green. Needs both lights calibrated; without a saved finish position it only freezes on Red.",
}):OnChanged(function(Value)
    AutoPassActive = Value
    if not Value then return end

    if not LightMonitor.Active then
        Options.RedLightMonitor:SetValue(true)
    end

    if not (Calibration.RedImageId and Calibration.GreenImageId) then
        Library:Notify("Calibrate both Red and Green lights first", 3)
    end

    if LightMonitor.Status == "Red" then
        FreezeMovement()
    elseif LightMonitor.Status == "Green" then
        ResumeMovement()
    end
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
