--!strict
-- Starts and wires the server services.

local Entrants = require(script.Entrants)
local Remotes = require(script.Remotes)
local BotService = require(script.BotService)
local CombatService = require(script.CombatService)
local LootService = require(script.LootService)
local RoundService = require(script.RoundService)

Remotes.setAliveCheck(Entrants.isPlayerAlive)
Remotes.onRequestAttack(function(player, slot, aim)
	local entrant = Entrants.fromPlayer(player)
	if entrant then
		CombatService.attack(entrant, slot, aim)
	end
end)

-- Every way out of a round goes through CombatService.knockOut.
Entrants.setDiedHandler(function(entrant)
	CombatService.knockOut(entrant, nil)
end)
RoundService.setLeaveHandler(function(entrant)
	CombatService.knockOut(entrant, nil)
end)
CombatService.onKnockout(function()
	Remotes.playersLeftChanged(Entrants.livingCount())
end)

RoundService.onPhaseChanged(BotService.onPhaseChanged)
RoundService.onPhaseChanged(CombatService.onPhaseChanged)
RoundService.onPhaseChanged(function(phase, round)
	LootService.onPhaseChanged(phase, round.arena)
end)

RoundService.start()
