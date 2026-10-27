--!strict
-- Drains hunger during the Active phase, applies starvation damage, and restores hunger
-- when an Entrant eats food from their server-side inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local LootTable = require(ReplicatedStorage.Shared.LootTable)
local Survival = require(ReplicatedStorage.Shared.Survival)
local CombatService = require(script.Parent.CombatService)
local Entrants = require(script.Parent.Entrants)
local LootService = require(script.Parent.LootService)

local SurvivalService = {}

local running = false
local sinceTick = 0

local function tick(dt: number)
	for _, entrant in Entrants.living() do
		local hunger, starvation = Survival.step(entrant.hunger, dt)
		local changed = hunger ~= entrant.hunger
		entrant.hunger = hunger
		if starvation > 0 then
			CombatService.damage(entrant, starvation, nil) -- also sends the new stats
		elseif changed then
			Entrants.sendStats(entrant)
		end
	end
end

-- Eats the food in `slot`. Returns false (and keeps the item) if it isn't food or the
-- Entrant is already full.
function SurvivalService.useItem(entrant: Entrants.Entrant, slot: number): boolean
	if not running or not entrant.alive then
		return false
	end
	local item = LootService.itemAt(entrant, slot)
	local restores = if item then LootTable.foodValue(item) else nil
	if not restores or entrant.hunger >= Config.Survival.MaxHunger then
		return false
	end
	LootService.takeItem(entrant, slot)
	entrant.hunger = Survival.eat(entrant.hunger, restores)
	Entrants.sendStats(entrant)
	return true
end

function SurvivalService.onPhaseChanged(phase: string)
	running = phase == "Active"
	sinceTick = 0
end

function SurvivalService.start()
	RunService.Heartbeat:Connect(function(dt: number)
		if not running then
			return
		end
		sinceTick += dt
		if sinceTick >= Config.Survival.TickSeconds then
			local elapsed = sinceTick
			sinceTick = 0
			tick(elapsed)
		end
	end)
end

return SurvivalService
