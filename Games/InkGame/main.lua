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
-- The Dalgona client module (ReplicatedStorage.Modules...Dalgona) is re-invoked
-- every round, spinning up a fresh set of closures. Two of those closures hold
-- all the state we need as upvalues:
--   * The failure/crack function (fires {FullyCracked=true} once you miss 5x) -
--     identified by the string constants "CrackAmount"/"FullyCracked".
--   * The RenderStepped loop that carves + reports completion - identified by
--     "DalgonaClickPart"/"MauioShakeOffset". It owns the carve counter
--     (v_u_152), the outline total (v_u_151) and the ~5% buffer (v_u_163), and
--     fires the real {Completed=true} on the per-round NewRem itself.
-- So instead of trying to replay a remote we can't see, we reach into those
-- upvalues: no-op the crack function to stop breaking, and push the carve
-- counter past the target so the game completes through its own code path
-- (own remote + own win cutscene).
local DalgonaGroup = Tabs.Dalgona:AddLeftGroupbox("Dalgona")

-- Executor-level API (all standard on Delta/Synapse-like executors).
local Getgc = getgc or (getgenv and getgenv().getgc)
local GetConstants = (debug and debug.getconstants) or getconstants
local GetUpvalues = (debug and debug.getupvalues) or getupvalues
local SetUpvalue = (debug and debug.setupvalue) or setupvalue
local IsLClosure = islclosure or is_l_closure

local DalgonaSupported = Getgc and GetConstants and GetUpvalues and SetUpvalue

local function FnHasConstants(Fn, Needles)
    local ok, Consts = pcall(GetConstants, Fn)
    if not ok or type(Consts) ~= "table" then
        return false
    end
    local Found = {}
    for _, Const in pairs(Consts) do
        if type(Const) == "string" then
            for _, Needle in ipairs(Needles) do
                if Const == Needle then
                    Found[Needle] = true
                end
            end
        end
    end
    for _, Needle in ipairs(Needles) do
        if not Found[Needle] then
            return false
        end
    end
    return true
end

-- Returns the live RenderStepped closure for the current round, preferring the
-- one whose upvalues still point at an outline model parented under workspace.
local function FindDalgonaRenderFn()
    if not DalgonaSupported then return nil end

    local ok, GC = pcall(Getgc, true)
    if not ok then return nil end

    local Fallback
    for _, Fn in pairs(GC) do
        if type(Fn) == "function" and (not IsLClosure or IsLClosure(Fn)) then
            if FnHasConstants(Fn, { "DalgonaClickPart", "MauioShakeOffset" }) then
                local upsOk, Ups = pcall(GetUpvalues, Fn)
                if upsOk and Ups then
                    for _, Value in pairs(Ups) do
                        if typeof(Value) == "Instance"
                            and Value.Name:match("Outline$")
                            and Value:IsDescendantOf(workspace) then
                            return Fn -- current, active round
                        end
                    end
                end
                Fallback = Fallback or Fn
            end
        end
    end
    return Fallback
end

-- A round is active while its outline model sits under workspace.Effects.
local function IsDalgonaActive()
    local Effects = workspace:FindFirstChild("Effects")
    if not Effects then return false end
    for _, Child in ipairs(Effects:GetChildren()) do
        if Child.Name:match("Outline$") then
            return true
        end
    end
    return false
end

--// Anti Crack \\--
-- Swap the crack function upvalue for a no-op so wrong clicks / timeout can
-- never escalate the crack counter to the break threshold.
local AntiCrackEnabled = false
local AntiCrackState = nil -- { Fn, Index, Original }

local function ApplyAntiCrack()
    local RenderFn = FindDalgonaRenderFn()
    if not RenderFn then return false end

    local ok, Ups = pcall(GetUpvalues, RenderFn)
    if not ok or not Ups then return false end

    for Index, Value in pairs(Ups) do
        if type(Value) == "function"
            and FnHasConstants(Value, { "CrackAmount", "FullyCracked" }) then
            AntiCrackState = { Fn = RenderFn, Index = Index, Original = Value }
            pcall(SetUpvalue, RenderFn, Index, function() end)
            return true
        end
    end
    return false
end

local function RestoreAntiCrack()
    if AntiCrackState then
        pcall(SetUpvalue, AntiCrackState.Fn, AntiCrackState.Index, AntiCrackState.Original)
        AntiCrackState = nil
    end
end

--// Auto Complete \\--
-- Recover the outline (still-to-carve) and shape (already carved) models from
-- the render loop's upvalues, then set the total (v_u_151 -> 0) and carve
-- counter (v_u_152 -> past target) so completion fires next frame.
local AutoCompleteEnabled = false
local CompleteDelay = 2

local function CompleteDalgona()
    local RenderFn = FindDalgonaRenderFn()
    if not RenderFn then return false, "No active Dalgona round." end

    local ok, Ups = pcall(GetUpvalues, RenderFn)
    if not ok or not Ups then return false, "Couldn't read upvalues." end

    local Outline, Shape
    for _, Value in pairs(Ups) do
        if typeof(Value) == "Instance" and Value:IsDescendantOf(workspace) then
            if Value.Name:match("Outline$") then
                Outline = Value
            end
        end
    end
    if Outline then
        local Base = Outline.Name:gsub("Outline$", "")
        for _, Value in pairs(Ups) do
            if typeof(Value) == "Instance" and Value.Name == Base and Value:IsDescendantOf(workspace) then
                Shape = Value
                break
            end
        end
    end
    if not (Outline and Shape) then
        return false, "Couldn't locate outline/shape."
    end

    -- v_u_151 == (children left in the outline) + (parts already carved into
    -- the shape as "DalgonaClickPart"), since carving only ever reparents parts
    -- out of the outline and into the shape.
    local Remaining = #Outline:GetChildren()
    local Carved = 0
    for _, Child in ipairs(Shape:GetChildren()) do
        if Child:IsA("BasePart") and Child.Name == "DalgonaClickPart" then
            Carved = Carved + 1
        end
    end
    local Total = Remaining + Carved
    if Total <= 0 then
        return false, "Round not ready yet."
    end

    local Changed = 0
    for Index, Value in pairs(Ups) do
        if type(Value) == "number" and Value == math.floor(Value) then
            if Value == Total then
                -- v_u_151 (outline total) -> 0 makes (v_u_152 >= total - buffer) true.
                pcall(SetUpvalue, RenderFn, Index, 0)
                Changed = Changed + 1
            elseif Carved >= 1 and Value == Carved and Value < Total then
                -- v_u_152 (carve counter) -> comfortably past the target.
                pcall(SetUpvalue, RenderFn, Index, Total + 10)
                Changed = Changed + 1
            end
        end
    end

    if Changed > 0 then
        return true, ("Completing (%d/%d carved)."):format(Carved, Total)
    end
    return false, "Couldn't match the carve counter."
end

--// Per-round watcher \\--
-- Re-applies anti-crack and auto-complete each round, since every round builds
-- fresh closures. getgc is only touched once per round per feature.
local WatcherRunning = false
local RoundAntiCrackApplied = false
local RoundAutoCompleted = false

local function StartDalgonaWatcher()
    if WatcherRunning then return end
    WatcherRunning = true
    task.spawn(function()
        while (AntiCrackEnabled or AutoCompleteEnabled) and not Library.Unloaded do
            if IsDalgonaActive() then
                if AntiCrackEnabled and not RoundAntiCrackApplied then
                    RoundAntiCrackApplied = ApplyAntiCrack()
                end
                if AutoCompleteEnabled and not RoundAutoCompleted then
                    RoundAutoCompleted = true -- claim the round up front so we fire once
                    task.spawn(function()
                        task.wait(CompleteDelay)
                        if AutoCompleteEnabled and IsDalgonaActive() then
                            CompleteDalgona()
                        end
                    end)
                end
            else
                RoundAntiCrackApplied = false
                RoundAutoCompleted = false
            end
            task.wait(0.3)
        end
        WatcherRunning = false
    end)
end

if not DalgonaSupported then
    DalgonaGroup:AddLabel("Your executor is missing getgc/debug upvalue support - Dalgona features unavailable.", true)
else
    DalgonaGroup:AddToggle("DalgonaAntiCrack", {
        Text = "Anti Crack",
        Default = false,
        Tooltip = "Neutralizes the crack function - you can't break the cookie even on wrong clicks",
    }):OnChanged(function(Value)
        AntiCrackEnabled = Value
        if Value then
            RoundAntiCrackApplied = false
            StartDalgonaWatcher()
        else
            RestoreAntiCrack()
            RoundAntiCrackApplied = false
        end
    end)

    DalgonaGroup:AddToggle("DalgonaAutoComplete", {
        Text = "Auto Complete",
        Default = false,
        Tooltip = "Auto-finishes each Dalgona round through the game's own completion (own remote + win cutscene)",
    }):OnChanged(function(Value)
        AutoCompleteEnabled = Value
        if Value then
            RoundAutoCompleted = false
            StartDalgonaWatcher()
        end
    end)

    DalgonaGroup:AddSlider("DalgonaCompleteDelay", {
        Text = "Complete Delay",
        Default = 2,
        Min = 0,
        Max = 10,
        Rounding = 1,
        Suffix = "s",
        Tooltip = "Seconds to wait after a round starts before auto-completing",
        Callback = function(Value)
            CompleteDelay = Value
        end,
    })

    DalgonaGroup:AddButton("Complete Now", function()
        local Ok, Message = CompleteDalgona()
        Library:Notify(Ok and ("Dalgona: " .. Message) or ("Dalgona: " .. tostring(Message)), 3)
    end)
end

Library:OnUnload(function()
    AntiCrackEnabled = false
    AutoCompleteEnabled = false
    RestoreAntiCrack()
end)

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
