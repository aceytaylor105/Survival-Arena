--!strict
-- Starts and wires the server services.

local Entrants = require(script.Entrants)
local Remotes = require(script.Remotes)
local BotService = require(script.BotService)
local LootService = require(script.LootService)
local RoundService = require(script.RoundService)

Remotes.setAliveCheck(Entrants.isPlayerAlive)

RoundService.onPhaseChanged(BotService.onPhaseChanged)
RoundService.onPhaseChanged(function(phase, round)
	LootService.onPhaseChanged(phase, round.arena)
end)

RoundService.start()
