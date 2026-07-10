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
    ["Hide n Seek"] = Window:AddTab("Hide n Seek", "ghost"),
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

--// Hide n Seek \\--
-- Same rhythm as Dalgona: the whole mode is driven through one wrapped remote -
-- ReplicatedStorage.Modules.RemoteWrapper over Remotes.TemporaryReachedBindable.
-- Every client action is a :FireServer(payload) on it:
--   { AttemptingToEscape = door } -> feed one held key into a working exit
--   { ESCAPING = door }           -> escape once that exit has all 3 keys (CANESCAPE)
--   { AttemptingToUnlock = door }  -> unlock a KeyNeeded door you hold the key for
--   { AttemptingToBarricadeDoor=..,IsInside=.. } -> barricade
-- Keys held live in LocalPlayer.CurrentKeys (children named Square/Triangle/Circle).
-- The real final exit is an EXITDOOR model with attribute ActuallyWorks (the
-- fakes carry DoesntWork); it needs all 3 keys, tracked via same-named boolean
-- attributes, and the server flips CANESCAPE once they're all in. Exits sit
-- under workspace.HideAndSeekMap.NEWFIXEDDOORS.Floor{1,2,3}.EXITDOORS.
--
-- Auto Escape is therefore a small state machine: grab the missing keys, then
-- feed them into the working exit and fire ESCAPING - all through the game's
-- own remote. The one thing the module doesn't expose is where the collectible
-- keys physically sit (the server just populates CurrentKeys), so we locate
-- world keys heuristically; that part may need live calibration per map.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HideSeekTab = Tabs["Hide n Seek"]
local HNS_KEYS = { "Square", "Triangle", "Circle" }

local function GetGuiParent()
    local ok, Hui = pcall(function() return gethui and gethui() end)
    if ok and Hui then return Hui end
    return game:GetService("CoreGui")
end

local function GetHRP()
    local Character = LocalPlayer.Character
    return Character and Character:FindFirstChild("HumanoidRootPart"), Character
end

local function IsHider()
    return LocalPlayer:GetAttribute("IsHider") == true
end

local function HeldKey(Name)
    local Folder = LocalPlayer:FindFirstChild("CurrentKeys")
    return Folder and Folder:FindFirstChild(Name) ~= nil
end

local function MissingKeys()
    local Missing = {}
    for _, Key in ipairs(HNS_KEYS) do
        if not HeldKey(Key) then
            table.insert(Missing, Key)
        end
    end
    return Missing
end

--// The wrapped remote \\--
-- Primary: rebuild the wrapper the same way the module does - firing it hits the
-- same underlying RemoteEvent, so the server sees an identical call. Fallback:
-- pull the live v_u_12 upvalue off the render closure (constants NEWFIXEDDOORS /
-- CANESCAPE) in case RemoteWrapper isn't safely re-entrant.
local HnSRemote = nil

local function AcquireRemoteViaModule()
    local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local Bindable = Remotes and Remotes:FindFirstChild("TemporaryReachedBindable")
    local Modules = ReplicatedStorage:FindFirstChild("Modules")
    local WrapperModule = Modules and Modules:FindFirstChild("RemoteWrapper")
    if not (Bindable and WrapperModule) then return nil end
    local ok, Wrapper = pcall(function()
        return require(WrapperModule)(Bindable)
    end)
    if ok and type(Wrapper) == "table" and type(Wrapper.FireServer) == "function" then
        return Wrapper
    end
    return nil
end

local function AcquireRemoteViaUpvalues()
    if not (Getgc and GetUpvalues) then return nil end
    local ok, GC = pcall(Getgc, true)
    if not ok then return nil end
    for _, Fn in pairs(GC) do
        if type(Fn) == "function" and (not IsLClosure or IsLClosure(Fn)) then
            if FnHasConstants(Fn, { "NEWFIXEDDOORS", "CANESCAPE" }) then
                local upsOk, Ups = pcall(GetUpvalues, Fn)
                if upsOk and Ups then
                    for _, Value in pairs(Ups) do
                        if type(Value) == "table" and type(Value.FireServer) == "function" then
                            return Value
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function GetRemote()
    if HnSRemote then return HnSRemote end
    HnSRemote = AcquireRemoteViaModule() or AcquireRemoteViaUpvalues()
    return HnSRemote
end

local function FireRemote(Payload)
    local Remote = GetRemote()
    if not Remote then return false end
    return pcall(function()
        Remote:FireServer(Payload)
    end)
end

--// Doors \\--
local function GetFixedDoors()
    local Map = workspace:FindFirstChild("HideAndSeekMap")
    return Map and Map:FindFirstChild("NEWFIXEDDOORS")
end

local function ForEachExitDoor(Callback)
    local Fixed = GetFixedDoors()
    if not Fixed then return end
    for _, Floor in ipairs(Fixed:GetChildren()) do
        if Floor.Name:match("^Floor") then
            local ExitDoors = Floor:FindFirstChild("EXITDOORS")
            if ExitDoors then
                for _, Door in ipairs(ExitDoors:GetChildren()) do
                    if Door:IsA("Model") and Door.Name == "EXITDOOR" then
                        Callback(Door)
                    end
                end
            end
        end
    end
end

local function DoorAnchor(Door)
    if Door.PrimaryPart then return Door.PrimaryPart end
    local DoorPart = Door:FindFirstChild("DoorPart")
    return DoorPart and DoorPart:FindFirstChild("MainDoorPart")
end

local function DoorKeyCount(Door)
    local Count = 0
    for _, Key in ipairs(HNS_KEYS) do
        if Door:GetAttribute(Key) then Count = Count + 1 end
    end
    return Count
end

-- The one exit that actually opens (fakes carry DoesntWork).
local function FindWorkingExit()
    local Working
    ForEachExitDoor(function(Door)
        if Door:GetAttribute("ActuallyWorks") and not Door:GetAttribute("DoesntWork") then
            Working = Working or Door
        end
    end)
    return Working
end

--// World keys (heuristic - calibrate live if empty) \\--
-- The module never touches the collectible keys, so we sweep the map for shape-
-- named parts/models that aren't the exit-door key slots (those live under
-- NEWFIXEDDOORS). Returns { { Instance = ..., Shape = "Square" }, ... }.
local function FindWorldKeys(FilterShape)
    local Map = workspace:FindFirstChild("HideAndSeekMap")
    local Result = {}
    if not Map then return Result end
    local Fixed = GetFixedDoors()
    for _, Desc in ipairs(Map:GetDescendants()) do
        local Shape
        for _, Key in ipairs(HNS_KEYS) do
            if Desc.Name == Key then Shape = Key break end
        end
        if Shape and (not FilterShape or FilterShape == Shape)
            and not (Fixed and Desc:IsDescendantOf(Fixed)) then
            local Anchor = (Desc:IsA("Model") and Desc.PrimaryPart) or (Desc:IsA("BasePart") and Desc)
            if Anchor then
                table.insert(Result, { Instance = Desc, Anchor = Anchor, Shape = Shape })
            end
        end
    end
    return Result
end

--// ESP \\--
local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "NeyHubHNS_ESP"
ESPFolder.Parent = GetGuiParent()

local HIDER_COLOR = Color3.fromRGB(60, 200, 90)
local SEEKER_COLOR = Color3.fromRGB(235, 60, 60)
local EXIT_OK_COLOR = Color3.fromRGB(70, 200, 120)
local EXIT_FAKE_COLOR = Color3.fromRGB(200, 60, 60)
local KEY_COLOR = Color3.fromRGB(240, 210, 70)

local function MakeHighlight(Adornee, FillColor)
    local H = Instance.new("Highlight")
    H.Adornee = Adornee
    H.FillColor = FillColor
    H.FillTransparency = 0.6
    H.OutlineColor = FillColor
    H.OutlineTransparency = 0
    H.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    H.Parent = ESPFolder
    return H
end

local function MakeBillboard(Adornee, Text, TextColor)
    local B = Instance.new("BillboardGui")
    B.Adornee = Adornee
    B.Size = UDim2.new(0, 220, 0, 34)
    B.StudsOffset = Vector3.new(0, 3, 0)
    B.AlwaysOnTop = true
    B.Parent = ESPFolder
    local L = Instance.new("TextLabel")
    L.BackgroundTransparency = 1
    L.Size = UDim2.new(1, 0, 1, 0)
    L.Font = Enum.Font.GothamBold
    L.TextSize = 14
    L.TextColor3 = TextColor or Color3.new(1, 1, 1)
    L.TextStrokeTransparency = 0.4
    L.Text = Text
    L.Parent = B
    return B
end

local PlayerESPEnabled = false
local ExitESPEnabled = false
local KeyESPEnabled = false

local PlayerESPObjects = {}
local ExitESPObjects = {}
local KeyESPObjects = {}

local function ClearList(List)
    for _, Obj in ipairs(List) do
        if Obj then Obj:Destroy() end
    end
    table.clear(List)
end

local function RebuildPlayerESP()
    ClearList(PlayerESPObjects)
    if not PlayerESPEnabled then return end
    local HRP = GetHRP()
    for _, Plr in ipairs(Players:GetPlayers()) do
        if Plr ~= LocalPlayer then
            local Char = Plr.Character
            local Anchor = Char and (Char:FindFirstChild("Head") or Char:FindFirstChild("HumanoidRootPart"))
            if Char and Anchor then
                local PlrHider = Plr:GetAttribute("IsHider") == true
                local Color = PlrHider and HIDER_COLOR or SEEKER_COLOR
                local Role = PlrHider and "HIDER" or "SEEKER"
                local Dist = HRP and math.floor((HRP.Position - Anchor.Position).Magnitude) or 0
                table.insert(PlayerESPObjects, MakeHighlight(Char, Color))
                table.insert(PlayerESPObjects,
                    MakeBillboard(Anchor, ("%s [%s] %dm"):format(Plr.Name, Role, Dist), Color))
            end
        end
    end
end

local function RebuildExitESP()
    ClearList(ExitESPObjects)
    if not ExitESPEnabled then return end
    ForEachExitDoor(function(Door)
        local Anchor = DoorAnchor(Door)
        if not Anchor then return end
        local Works = Door:GetAttribute("ActuallyWorks") and not Door:GetAttribute("DoesntWork")
        local Color = Works and EXIT_OK_COLOR or EXIT_FAKE_COLOR
        local Text = Works and ("EXIT  " .. DoorKeyCount(Door) .. "/3 keys") or "FAKE / LOCKED"
        table.insert(ExitESPObjects, MakeHighlight(Door, Color))
        table.insert(ExitESPObjects, MakeBillboard(Anchor, Text, Color))
    end)
end

local function RebuildKeyESP()
    ClearList(KeyESPObjects)
    if not KeyESPEnabled then return end
    for _, Entry in ipairs(FindWorldKeys()) do
        table.insert(KeyESPObjects, MakeHighlight(Entry.Instance, KEY_COLOR))
        table.insert(KeyESPObjects, MakeBillboard(Entry.Anchor, "KEY: " .. Entry.Shape, KEY_COLOR))
    end
end

local ESPLoopRunning = false
local function StartESPLoop()
    if ESPLoopRunning then return end
    ESPLoopRunning = true
    task.spawn(function()
        while (PlayerESPEnabled or ExitESPEnabled or KeyESPEnabled) and not Library.Unloaded do
            RebuildPlayerESP()
            RebuildExitESP()
            RebuildKeyESP()
            task.wait(0.5)
        end
        ClearList(PlayerESPObjects)
        ClearList(ExitESPObjects)
        ClearList(KeyESPObjects)
        ESPLoopRunning = false
    end)
end

--// Auto Escape \\--
local AutoEscapeEnabled = false
local AutoEscapeRunning = false
local EscapeStatus = "Idle"

local function TeleportTo(Position, Offset)
    local HRP = GetHRP()
    if not HRP then return false end
    HRP.CFrame = CFrame.new(Position + (Offset or Vector3.new(0, 1.5, 0)))
    return true
end

-- Teleport to the nearest missing key and try to pick it up. Returns true only
-- once no keys are missing; the escape loop re-checks each tick.
local function CollectNearestMissingKey()
    local Missing = MissingKeys()
    if #Missing == 0 then return true end
    local HRP = GetHRP()
    if not HRP then return false end

    local NeedSet = {}
    for _, K in ipairs(Missing) do NeedSet[K] = true end

    local Best, BestDist
    for _, Entry in ipairs(FindWorldKeys()) do
        if NeedSet[Entry.Shape] then
            local D = (HRP.Position - Entry.Anchor.Position).Magnitude
            if not BestDist or D < BestDist then
                Best, BestDist = Entry, D
            end
        end
    end
    if not Best then
        EscapeStatus = "No world key found (needs calibration)"
        return false
    end

    EscapeStatus = "Grabbing " .. Best.Shape .. " key"
    TeleportTo(Best.Anchor.Position, Vector3.new(0, 1.5, 0))
    -- pickup is either a Touched trigger (the teleport covers it) or a prompt
    if fireproximityprompt then
        for _, D in ipairs(Best.Instance:GetDescendants()) do
            if D:IsA("ProximityPrompt") then
                pcall(fireproximityprompt, D)
            end
        end
    end
    return false
end

local function DoEscape()
    local Door = FindWorkingExit()
    if not Door then
        EscapeStatus = "Looking for the working exit"
        return
    end
    local Anchor = DoorAnchor(Door)
    if not Anchor then return end

    EscapeStatus = "Feeding keys into exit"
    TeleportTo(Anchor.Position, Vector3.new(0, 1.5, 0))
    for _, Key in ipairs(HNS_KEYS) do
        if HeldKey(Key) and not Door:GetAttribute(Key) then
            FireRemote({ AttemptingToEscape = Door })
            task.wait(0.4)
        end
    end
    if Door:GetAttribute("CANESCAPE") then
        EscapeStatus = "Escaping!"
        FireRemote({ ESCAPING = Door })
    end
end

local function StartAutoEscape()
    if AutoEscapeRunning then return end
    AutoEscapeRunning = true
    task.spawn(function()
        while AutoEscapeEnabled and not Library.Unloaded do
            if not IsHider() then
                EscapeStatus = "Not a hider"
            elseif LocalPlayer:GetAttribute("HNSDidEscape") then
                EscapeStatus = "Escaped"
            elseif #MissingKeys() > 0 then
                CollectNearestMissingKey()
            else
                DoEscape()
            end
            task.wait(0.5)
        end
        AutoEscapeRunning = false
        EscapeStatus = "Idle"
    end)
end

--// UI \\--
local EscapeGroup = HideSeekTab:AddLeftGroupbox("Auto Escape (Hider)")

local EscapeStatusLabel = EscapeGroup:AddLabel("Status: Idle", true)

EscapeGroup:AddToggle("HNSAutoEscape", {
    Text = "Auto Escape",
    Default = false,
    Tooltip = "Coleta as chaves que faltam e escapa pela saida que funciona, tudo pelo remoto do jogo",
}):OnChanged(function(Value)
    AutoEscapeEnabled = Value
    if Value then StartAutoEscape() end
end)

EscapeGroup:AddButton("Escape Now", function()
    task.spawn(function()
        if not IsHider() then
            Library:Notify("Hide n Seek: voce nao e hider.", 3)
            return
        end
        if #MissingKeys() > 0 then
            CollectNearestMissingKey()
        else
            DoEscape()
        end
    end)
end)

task.spawn(function()
    while not Library.Unloaded do
        pcall(function() EscapeStatusLabel:SetText("Status: " .. EscapeStatus) end)
        task.wait(0.3)
    end
end)

local ESPGroup = HideSeekTab:AddRightGroupbox("ESP")

ESPGroup:AddToggle("HNSPlayerESP", {
    Text = "Player ESP",
    Default = false,
    Tooltip = "Destaca jogadores: verde = hider, vermelho = seeker/hunter (com distancia)",
}):OnChanged(function(Value)
    PlayerESPEnabled = Value
    if Value then StartESPLoop() else RebuildPlayerESP() end
end)

ESPGroup:AddToggle("HNSExitESP", {
    Text = "Exit ESP",
    Default = false,
    Tooltip = "Destaca as saidas: verde = funciona (mostra chaves X/3), vermelho = falsa/trancada",
}):OnChanged(function(Value)
    ExitESPEnabled = Value
    if Value then StartESPLoop() else RebuildExitESP() end
end)

ESPGroup:AddToggle("HNSKeyESP", {
    Text = "Key ESP",
    Default = false,
    Tooltip = "Destaca as chaves espalhadas no mapa (pode precisar de calibracao no jogo)",
}):OnChanged(function(Value)
    KeyESPEnabled = Value
    if Value then StartESPLoop() else RebuildKeyESP() end
end)

Library:OnUnload(function()
    AutoEscapeEnabled = false
    PlayerESPEnabled = false
    ExitESPEnabled = false
    KeyESPEnabled = false
    if ESPFolder then
        ESPFolder:Destroy()
    end
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
