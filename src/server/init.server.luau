--!strict
-- Starts and wires the server services.

local Entrants = require(script.Entrants)
local Remotes = require(script.Remotes)
local BotService = require(script.BotService)
local CollapseService = require(script.CollapseService)
local CombatService = require(script.CombatService)
local LootService = require(script.LootService)
local RoundService = require(script.RoundService)
local SurvivalService = require(script.SurvivalService)

Remotes.setAliveCheck(Entrants.isPlayerAlive)
Remotes.onRequestAttack(function(player, slot, aim)
	local entrant = Entrants.fromPlayer(player)
	if entrant then
		CombatService.attack(entrant, slot, aim)
	end
end)
Remotes.onRequestUseItem(function(player, slot)
	local entrant = Entrants.fromPlayer(player)
	if entrant then
		SurvivalService.useItem(entrant, slot)
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
RoundService.onPhaseChanged(SurvivalService.onPhaseChanged)
RoundService.onPhaseChanged(function(phase, round)
	LootService.onPhaseChanged(phase, round.arena)
	CollapseService.onPhaseChanged(phase, round.arena, round.activeStartedAt)
end)

CollapseService.start()
SurvivalService.start()
RoundService.start()
