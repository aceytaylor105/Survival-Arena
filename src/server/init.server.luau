--!strict
-- Starts and wires the server services.

local Entrants = require(script.Entrants)
local Remotes = require(script.Remotes)
local BotService = require(script.BotService)
local RoundService = require(script.RoundService)

Remotes.setAliveCheck(Entrants.isPlayerAlive)

RoundService.onPhaseChanged(BotService.onPhaseChanged)

RoundService.start()
