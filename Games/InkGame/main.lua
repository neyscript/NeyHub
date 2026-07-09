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
-- Calibrated live against the actual doll via the Element Inspector, then
-- baked in here as constants - fully automatic now, no setup needed.
local RED_IMAGE_ID = "rbxassetid://88400194373338"
local GREEN_IMAGE_ID = "rbxassetid://94760723422266"
local FINISH_POSITION = Vector3.new(-24.854, 1024.243, 122.259)

local LocalPlayer = game:GetService("Players").LocalPlayer

local AutoPassGroup = Tabs["Red Light"]:AddLeftGroupbox("Auto Pass")

local LightStatus = "Unknown"
local LightStatusListeners = {}
local function OnLightStatusChanged(Callback)
    table.insert(LightStatusListeners, Callback)
end

local function SetLightStatus(Status)
    if LightStatus == Status then return end
    LightStatus = Status

    for _, Callback in ipairs(LightStatusListeners) do
        task.spawn(Callback, Status)
    end
end

local TrafficLightConnection = nil
local PlayerGuiConnection = nil

local function HandleTrafficLightImageChanged(Instance)
    local Image = Instance.Image

    if Image == RED_IMAGE_ID then
        SetLightStatus("Red")
    elseif Image == GREEN_IMAGE_ID then
        SetLightStatus("Green")
    end
end

local function TryBindTrafficLight(Instance)
    if Instance.Name ~= "TrafficLightEmpty" or not (Instance:IsA("ImageLabel") or Instance:IsA("ImageButton")) then
        return
    end

    if TrafficLightConnection then
        TrafficLightConnection:Disconnect()
    end

    TrafficLightConnection = Instance:GetPropertyChangedSignal("Image"):Connect(function()
        HandleTrafficLightImageChanged(Instance)
    end)
    HandleTrafficLightImageChanged(Instance)
end

local function StartLightMonitor()
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return end

    for _, Instance in ipairs(PlayerGui:GetDescendants()) do
        TryBindTrafficLight(Instance)
    end
    PlayerGuiConnection = PlayerGui.DescendantAdded:Connect(TryBindTrafficLight)
end

StartLightMonitor()

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
    Humanoid:MoveTo(FINISH_POSITION)
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
    Tooltip = "Freezes on Red, auto-walks to the finish line on Green",
}):OnChanged(function(Value)
    AutoPassActive = Value
    if not Value then return end

    if LightStatus == "Red" then
        FreezeMovement()
    elseif LightStatus == "Green" then
        ResumeMovement()
    end
end)

Library:OnUnload(function()
    if TrafficLightConnection then
        TrafficLightConnection:Disconnect()
    end
    if PlayerGuiConnection then
        PlayerGuiConnection:Disconnect()
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
