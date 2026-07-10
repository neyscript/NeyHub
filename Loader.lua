--[[
    Ney Hub - universal loader.

    This is the only loadstring the end user ever needs, in any game:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/neyscript/NeyHub/main/Loader.lua"))()

    It checks game.PlaceId against the table below and only loads a
    script if the current place is one Ney Hub actually supports.

    To add a new game: drop its script in Games/<GameName>/main.lua
    and add its PlaceId + path to SUPPORTED_GAMES below.
]]

local REPO = "https://raw.githubusercontent.com/neyscript/NeyHub/main/"

-- PlaceId -> path (relative to REPO) of that game's script
-- Some experiences use more than one PlaceId (lobby vs. actual match place),
-- so a single game can have multiple entries pointing at the same script.
local SUPPORTED_GAMES = {
    [119099244949868] = "Games/InkGame/main.lua", -- [🔥] Ink Game (lobby)
    [125009265613167] = "Games/InkGame/main.lua", -- [🔥] Ink Game (match)
    [99567941238278] = "Games/InkGame/main.lua", -- [🔥] Ink Game (universe root place)
    [90407707718652] = "Games/InkGame/main.lua", -- [🔥] Ink Game (training center)
}

local ScriptPath = SUPPORTED_GAMES[game.PlaceId]

if not ScriptPath then
    local Message = "Ney Hub doesn't support this game yet."

    local Notified = pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Ney Hub",
            Text = Message,
            Duration = 6,
        })
    end)

    if not Notified then
        warn("[Ney Hub] " .. Message)
    end

    return
end

loadstring(game:HttpGet(REPO .. ScriptPath))()
