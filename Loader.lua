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
local SUPPORTED_GAMES = {
    [99567941238278] = "Games/InkGame/main.lua", -- [🔥] Ink Game
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
