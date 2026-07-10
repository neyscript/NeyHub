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
    Mingle = Window:AddTab("Mingle", "zap"),
    ["Glass Bridge"] = Window:AddTab("Glass Bridge", "footprints"),
    Pentathlon = Window:AddTab("Pentathlon", "medal"),
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

--// World keys \\--
-- Found live via Dex: collectible keys are dropped parts under workspace.Effects
-- named "DroppedKey<Shape>" (DroppedKeySquare / DroppedKeyTriangle / DroppedKeyCircle).
-- The <Shape> suffix is the key you receive, so we can target exactly the one
-- that's still missing. NB: they seem to stream in only once you're near
-- (StreamingEnabled), so distant keys can be invisible until approached.
-- Returns { { Instance = ..., Anchor = ..., Shape = "Square" }, ... }.
local function KeyShapeFromName(Name)
    local Suffix = Name:match("^DroppedKey(%a+)$")
    if not Suffix then return nil end
    for _, Key in ipairs(HNS_KEYS) do
        if Suffix == Key then return Key end
    end
    return Suffix -- still a key, just an unexpected shape name
end

local function KeyAnchor(Inst)
    if Inst:IsA("BasePart") then return Inst end
    if Inst:IsA("Model") then return Inst.PrimaryPart or Inst:FindFirstChildWhichIsA("BasePart") end
    return nil
end

local function FindWorldKeys(FilterShape)
    local Result = {}
    local Effects = workspace:FindFirstChild("Effects")
    if not Effects then return Result end
    for _, Desc in ipairs(Effects:GetChildren()) do
        local Shape = KeyShapeFromName(Desc.Name)
        if Shape and (not FilterShape or FilterShape == Shape) then
            local Anchor = KeyAnchor(Desc)
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
        EscapeStatus = "No key loaded nearby (get closer / none left)"
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

--// Mingle \\--
-- The QTE system (ModuleScript HBGQTE, shared by Mingle and any other QTE game)
-- is client-authoritative: the client decides hit vs miss itself and only then
-- tells the server, firing Character.RemoteForQTE (hit) or FailRemoteForQTE
-- (miss) with no timing proof (RemoteForQTE:FireServer() takes no args). The
-- returned module table exposes ActiveButtons (the live on-screen prompts) and
-- Pressed(failed, button); calling Pressed(false, button) forces the hit branch
-- and sets PressedOnce/Tweening so the fail timeout never fires the miss remote.
-- Auto QTE just pushes every active prompt through the game's own hit path.
local MingleTab = Tabs.Mingle
local MingleGroup = MingleTab:AddLeftGroupbox("Mingle")

-- The QTE module is a session singleton (required once), so find it by its field
-- signature and cache it - only touch getgc while we haven't found it yet.
local QTEModule = nil

local function FindQTEModule()
    if QTEModule then return QTEModule end
    if not Getgc then return nil end
    local ok, GC = pcall(Getgc, true)
    if not ok then return nil end
    for _, Value in pairs(GC) do
        if type(Value) == "table"
            and type(rawget(Value, "Pressed")) == "function"
            and type(rawget(Value, "SetUpButton")) == "function"
            and type(rawget(Value, "ActiveButtons")) == "table" then
            QTEModule = Value
            return QTEModule
        end
    end
    return nil
end

-- Push every active, not-yet-pressed prompt through the hit path. Each runs in
-- its own thread (the hit branch yields ~0.32s on the screen flash) and we guard
-- a nil Data table so Pressed can't error before it fires the success remote.
local function PassActiveQTEs(Module)
    local Count = 0
    for _, Button in pairs(Module.ActiveButtons) do
        if type(Button) == "table" and typeof(Button.Outer) == "Instance"
            and not Button.Outer:GetAttribute("PressedOnce") then
            if type(Button.Data) ~= "table" then
                Button.Data = {}
            end
            task.spawn(function()
                pcall(Module.Pressed, false, Button)
            end)
            Count = Count + 1
        end
    end
    return Count
end

local AutoQTEEnabled = false
local AutoQTERunning = false

local function StartAutoQTE()
    if AutoQTERunning then return end
    AutoQTERunning = true
    task.spawn(function()
        while AutoQTEEnabled and not Library.Unloaded do
            local Module = FindQTEModule()
            if Module then
                PassActiveQTEs(Module)
                task.wait(0.05)
            else
                task.wait(0.5) -- module not loaded yet (no QTE game running)
            end
        end
        AutoQTERunning = false
    end)
end

if not Getgc then
    MingleGroup:AddLabel("Seu executor nao tem getgc - Auto QTE indisponivel.", true)
else
    MingleGroup:AddToggle("MingleAutoQTE", {
        Text = "Auto QTE",
        Default = false,
        Tooltip = "Acerta todo QTE automaticamente pelo proprio caminho de acerto do jogo. Serve pro Mingle e qualquer jogo com o mesmo QTE - liga numa partida de Tug pra testar.",
    }):OnChanged(function(Value)
        AutoQTEEnabled = Value
        if Value then StartAutoQTE() end
    end)

    MingleGroup:AddButton("Force QTE Pass", function()
        local Module = FindQTEModule()
        if not Module then
            Library:Notify("Mingle: QTE module nao encontrado (entra num QTE primeiro).", 3)
            return
        end
        Library:Notify(("Mingle: %d QTE(s) passados."):format(PassActiveQTEs(Module)), 3)
    end)
end

Library:OnUnload(function()
    AutoQTEEnabled = false
end)

--// Glass Bridge \\--
-- Which tile breaks is marked by the attribute "exploitingisevil" on each
-- panel's PrimaryPart (a troll name, but it's what the game reads on Touch,
-- lines 213-216 of GlassBridgeClient). Panels live under
-- workspace.GlassBridge.GlassHolder -> rows -> Model tiles (each with a
-- PrimaryPart). Death is client-driven: the Touched handler (v_u_56) fires
-- { TouchedGlass = panel, ... } to the server and runs the local kill v_u_48,
-- which fires { FallingPlayer = true, ... }. So:
--   * ESP just reads the attribute and colours tiles green/red.
--   * Anti Break gates v_u_56 (v_u_25 = true -> the whole handler no-ops, so no
--     TouchedGlass, no shatter) and no-ops v_u_48 everywhere it's held (kills the
--     fall path too). Reached through upvalues, same as Dalgona.
local GlassTab = Tabs["Glass Bridge"]

local GLASS_SAFE_COLOR = Color3.fromRGB(60, 200, 90)
local GLASS_BREAK_COLOR = Color3.fromRGB(235, 60, 60)

-- With pity on, only "exploitingisevil" tiles that also flag ActuallyKilling
-- break; with pity off, every "exploitingisevil" tile breaks.
local function GlassPanelBreaks(PrimaryPart)
    if not PrimaryPart:GetAttribute("exploitingisevil") then
        return false
    end
    if workspace:GetAttribute("GlassBridgePityEnabled") then
        return PrimaryPart:GetAttribute("ActuallyKilling") == true
    end
    return true
end

local function ForEachGlassPanel(Callback)
    local Bridge = workspace:FindFirstChild("GlassBridge")
    local Holder = Bridge and Bridge:FindFirstChild("GlassHolder")
    if not Holder then return end
    for _, Row in ipairs(Holder:GetChildren()) do
        for _, Tile in ipairs(Row:GetChildren()) do
            if Tile:IsA("Model") and Tile.PrimaryPart then
                Callback(Tile, Tile.PrimaryPart)
            end
        end
    end
end

--// Glass ESP \\--
local GlassESPEnabled = false
local GlassESPRunning = false
local GlassESPObjects = {}

local function RebuildGlassESP()
    ClearList(GlassESPObjects)
    if not GlassESPEnabled then return end
    ForEachGlassPanel(function(Tile, Primary)
        local Color = GlassPanelBreaks(Primary) and GLASS_BREAK_COLOR or GLASS_SAFE_COLOR
        table.insert(GlassESPObjects, MakeHighlight(Tile, Color))
    end)
end

local function StartGlassESP()
    if GlassESPRunning then return end
    GlassESPRunning = true
    task.spawn(function()
        while GlassESPEnabled and not Library.Unloaded do
            RebuildGlassESP()
            task.wait(0.5)
        end
        ClearList(GlassESPObjects)
        GlassESPRunning = false
    end)
end

--// Anti Break \\--
local GlassSupported = Getgc and GetConstants and GetUpvalues and SetUpvalue
local AntiBreakEnabled = false
local AntiBreakRoundApplied = false
local AntiBreakWatcherRunning = false
local AntiBreakState = {}

local function ApplyAntiBreak()
    if not GlassSupported then return false, "no getgc/upvalue support" end
    local ok, GC = pcall(Getgc, true)
    if not ok then return false, "getgc failed" end

    local KillFn, TouchFn
    for _, Fn in pairs(GC) do
        if type(Fn) == "function" and (not IsLClosure or IsLClosure(Fn)) then
            if not KillFn and FnHasConstants(Fn, { "FallingPlayer", "funnydeath" }) then
                KillFn = Fn
            end
            if not TouchFn and FnHasConstants(Fn, { "TouchedGlass", "exploitingisevil" }) then
                TouchFn = Fn
            end
        end
    end
    if not (KillFn or TouchFn) then
        return false, "closures not found (round active?)"
    end

    -- Gate the Touched handler: its first boolean upvalue is v_u_25; true = no-op.
    if TouchFn then
        local upsOk, Ups = pcall(GetUpvalues, TouchFn)
        if upsOk and Ups then
            for Index = 1, 32 do
                if type(Ups[Index]) == "boolean" then
                    table.insert(AntiBreakState, { Fn = TouchFn, Index = Index, Original = Ups[Index] })
                    pcall(SetUpvalue, TouchFn, Index, true)
                    break
                end
            end
        end
    end

    -- No-op the kill function wherever it is held (Touched path + fall check).
    if KillFn then
        for _, Fn in pairs(GC) do
            if type(Fn) == "function" and (not IsLClosure or IsLClosure(Fn)) then
                local upsOk, Ups = pcall(GetUpvalues, Fn)
                if upsOk and Ups then
                    for Index, Value in pairs(Ups) do
                        if Value == KillFn then
                            table.insert(AntiBreakState, { Fn = Fn, Index = Index, Original = Value })
                            pcall(SetUpvalue, Fn, Index, function() end)
                        end
                    end
                end
            end
        end
    end

    if #AntiBreakState > 0 then
        return true, ("neutralized %d hook(s)"):format(#AntiBreakState)
    end
    return false, "found closures but couldn't patch"
end

local function RestoreAntiBreak()
    for _, S in ipairs(AntiBreakState) do
        pcall(SetUpvalue, S.Fn, S.Index, S.Original)
    end
    table.clear(AntiBreakState)
end

local function GlassRoundActive()
    local Char = LocalPlayer.Character
    if Char and Char:FindFirstChild("PlayingGlassBridge") then
        return true
    end
    local Bridge = workspace:FindFirstChild("GlassBridge")
    local Holder = Bridge and Bridge:FindFirstChild("GlassHolder")
    return Holder ~= nil and #Holder:GetChildren() > 0
end

-- Every round builds fresh closures, so re-apply per round (like Dalgona).
local function StartAntiBreakWatcher()
    if AntiBreakWatcherRunning then return end
    AntiBreakWatcherRunning = true
    task.spawn(function()
        while AntiBreakEnabled and not Library.Unloaded do
            if GlassRoundActive() then
                if not AntiBreakRoundApplied then
                    AntiBreakRoundApplied = (ApplyAntiBreak())
                end
            elseif AntiBreakRoundApplied then
                RestoreAntiBreak()
                AntiBreakRoundApplied = false
            end
            task.wait(0.5)
        end
        RestoreAntiBreak()
        AntiBreakRoundApplied = false
        AntiBreakWatcherRunning = false
    end)
end

--// UI \\--
local GlassESPGroup = GlassTab:AddLeftGroupbox("ESP")

GlassESPGroup:AddToggle("GlassESP", {
    Text = "Glass ESP",
    Default = false,
    Tooltip = "Verde = vidro seguro, vermelho = quebra (le o atributo exploitingisevil). So andar no verde.",
}):OnChanged(function(Value)
    GlassESPEnabled = Value
    if Value then StartGlassESP() else RebuildGlassESP() end
end)

local GlassSafetyGroup = GlassTab:AddRightGroupbox("Safety")

if not GlassSupported then
    GlassSafetyGroup:AddLabel("Seu executor nao tem getgc - Anti Break indisponivel.", true)
else
    GlassSafetyGroup:AddToggle("GlassAntiBreak", {
        Text = "Anti Break (experimental)",
        Default = false,
        Tooltip = "Neutraliza o handler de toque e a funcao de morte pelos upvalues. Se o break for client-driven, voce nao quebra nem pisando no errado.",
    }):OnChanged(function(Value)
        AntiBreakEnabled = Value
        if Value then
            AntiBreakRoundApplied = false
            StartAntiBreakWatcher()
        else
            RestoreAntiBreak()
            AntiBreakRoundApplied = false
        end
    end)

    GlassSafetyGroup:AddButton("Apply Now", function()
        local Ok, Message = ApplyAntiBreak()
        Library:Notify("Glass Bridge: " .. tostring(Message), 3)
        if Ok then AntiBreakRoundApplied = true end
    end)
end

Library:OnUnload(function()
    GlassESPEnabled = false
    AntiBreakEnabled = false
    RestoreAntiBreak()
end)

--// Pentathlon \\--
-- Pentathlon is 5 mini-games (Ddakji, Flying Stone, Gonggi, Spinning Top, Jegi).
-- Each one, when cleared, calls v_u_25.RunServerGame(game, "Action", data), which
-- is just Remote:FireServer(game.GUID, "Action", data). The server trusts the
-- client's outcome (Spinning Top sends Thrown {} on success vs Thrown {Failed=true}
-- on timeout - only the flag differs), so we can fire the success payload directly.
-- We reach the module (v_u_25: RunServerGame + AddActiveGame + Start) and the local
-- player's current game object (metatable = the class carrying .Ddakji etc., Active,
-- and our character in PlayersIndex) through getgc, then push the win action. One
-- button per game since the game object doesn't record which mini-game it is - you
-- click the one you're in. Success payloads pulled straight from the decompile:
--   Spinning Top -> "Thrown" {} then "Tied" {}
--   Jegi         -> "Kick" { Lose = false } x6 (client counter caps at 6)
--   Gonggi       -> "GotPiece" { Name } per piece, then "TimeSlowFinish"
--   Ddakji       -> "Thrown" { Power, Position }
--   Flying Stone -> "Thrown" { ThrowPower, Origin, Direction }
local PentTab = Tabs.Pentathlon
local PentSupported = Getgc and true or false
local PentModule = nil
local PentThrowPower = 0.5

local function FindPentModule()
    if PentModule and type(rawget(PentModule, "RunServerGame")) == "function" then
        return PentModule
    end
    if not Getgc then return nil end
    local ok, GC = pcall(Getgc, true)
    if not ok then return nil end
    for _, Value in pairs(GC) do
        if type(Value) == "table"
            and type(rawget(Value, "RunServerGame")) == "function"
            and type(rawget(Value, "AddActiveGame")) == "function"
            and type(rawget(Value, "Start")) == "function" then
            PentModule = Value
            return Value
        end
    end
    return nil
end

-- The active game object holding our character (metatable = the game class,
-- recognised by its .Ddakji method). Re-found each press since it's per-round.
local function FindCurrentGame()
    if not Getgc then return nil end
    local Char = LocalPlayer.Character
    if not Char then return nil end
    local ok, GC = pcall(Getgc, true)
    if not ok then return nil end
    for _, Value in pairs(GC) do
        if type(Value) == "table" and rawget(Value, "GUID")
            and type(rawget(Value, "PlayersIndex")) == "table" then
            local Mt = getmetatable(Value)
            if type(Mt) == "table" and type(rawget(Mt, "Ddakji")) == "function"
                and Value.Active and Value.PlayersIndex[Char] then
                return Value
            end
        end
    end
    return nil
end

-- Returns module, game, error-message.
local function PentReady()
    local Module = FindPentModule()
    if not Module then return nil, nil, "modulo nao carregado (entra no Pentathlon)" end
    local Game = FindCurrentGame()
    if not Game then return nil, nil, "jogo atual nao encontrado (entra numa prova)" end
    return Module, Game, nil
end

local function PentFire(Module, Game, Action, Data)
    return pcall(function()
        Module.RunServerGame(Game, Action, Data)
    end)
end

-- Aim a point on the map for the throw games (camera forward onto PentathlonMap).
local function PentAimPosition()
    local Char = LocalPlayer.Character
    local HRP = Char and Char:FindFirstChild("HumanoidRootPart")
    if not HRP then return Vector3.new() end
    local Cam = workspace.CurrentCamera
    local Origin = HRP.Position
    local Direction = (Cam and Cam.CFrame.LookVector) or HRP.CFrame.LookVector
    local Map = workspace:FindFirstChild("PentathlonMap")
    if Map then
        local Params = RaycastParams.new()
        Params.FilterType = Enum.RaycastFilterType.Include
        Params.FilterDescendantsInstances = { Map }
        local Hit = workspace:Raycast(Origin, Direction * 200, Params)
        if Hit then return Hit.Position end
    end
    return Origin + Direction * 10
end

local PentGroup = PentTab:AddLeftGroupbox("Auto Pass (clique no jogo atual)")

if not PentSupported then
    PentGroup:AddLabel("Seu executor nao tem getgc - Pentathlon indisponivel.", true)
else
    PentGroup:AddButton("Spinning Top - Pass", function()
        local Module, Game, Err = PentReady()
        if not Module then Library:Notify("Pentathlon: " .. Err, 3) return end
        task.spawn(function()
            PentFire(Module, Game, "Thrown", {})
            task.wait(0.6)
            PentFire(Module, Game, "Tied", {})
        end)
        Library:Notify("Pentathlon (Spinning Top): enviado", 3)
    end)

    PentGroup:AddButton("Jegi - Pass", function()
        local Module, Game, Err = PentReady()
        if not Module then Library:Notify("Pentathlon: " .. Err, 3) return end
        task.spawn(function()
            for _ = 1, 6 do
                PentFire(Module, Game, "Kick", { Lose = false })
                task.wait(0.35)
            end
        end)
        Library:Notify("Pentathlon (Jegi): mandando 6 kicks", 3)
    end)

    PentGroup:AddButton("Ddakji - Pass", function()
        local Module, Game, Err = PentReady()
        if not Module then Library:Notify("Pentathlon: " .. Err, 3) return end
        PentFire(Module, Game, "Thrown", {
            Power = PentThrowPower,
            Position = PentAimPosition(),
        })
        Library:Notify("Pentathlon (Ddakji): enviado (Power " .. PentThrowPower .. ")", 3)
    end)

    PentGroup:AddButton("Flying Stone - Pass", function()
        local Module, Game, Err = PentReady()
        if not Module then Library:Notify("Pentathlon: " .. Err, 3) return end
        local Char = LocalPlayer.Character
        local HRP = Char and Char:FindFirstChild("HumanoidRootPart")
        local Origin = HRP and HRP.Position or Vector3.new()
        local Cam = workspace.CurrentCamera
        local Direction = (Cam and Cam.CFrame.LookVector) or (HRP and HRP.CFrame.LookVector) or Vector3.new(0, 0, -1)
        PentFire(Module, Game, "Thrown", {
            ThrowPower = PentThrowPower,
            Origin = Origin,
            Direction = Direction,
        })
        Library:Notify("Pentathlon (Flying Stone): enviado", 3)
    end)

    PentGroup:AddButton("Gonggi - Pass", function()
        local Module, Game, Err = PentReady()
        if not Module then Library:Notify("Pentathlon: " .. Err, 3) return end
        task.spawn(function()
            -- best-effort: report every gonggi piece we can find, then finish
            local Map = workspace:FindFirstChild("PentathlonMap")
            local Fired = 0
            if Map then
                for _, Desc in ipairs(Map:GetDescendants()) do
                    if Desc:IsA("BasePart") and Desc.Name:lower():find("gonggi") then
                        PentFire(Module, Game, "GotPiece", { Name = Desc.Name })
                        Fired = Fired + 1
                        task.wait(0.1)
                    end
                end
            end
            PentFire(Module, Game, "TimeSlowFinish")
            Library:Notify(("Pentathlon (Gonggi): %d pecas + finish"):format(Fired), 3)
        end)
    end)

    PentGroup:AddSlider("PentThrowPower", {
        Text = "Throw Power",
        Default = 0.5,
        Min = 0,
        Max = 1,
        Rounding = 2,
        Tooltip = "Power usado no Ddakji / Flying Stone. Calibra testando (zona verde ~0.4-0.6).",
        Callback = function(Value)
            PentThrowPower = Value
        end,
    })

    PentGroup:AddButton("Detect Game", function()
        local Module = FindPentModule()
        local Game = FindCurrentGame()
        Library:Notify(("Pentathlon: module=%s game=%s"):format(
            Module and "OK" or "nao", Game and tostring(Game.GUID) or "nao"), 4)
    end)
end

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
