--!strict
-- Server-side R15 bots, so one person can test a full round. Studio only by default
-- (Config.Bots). Bots loot the nearest crate, fight any Entrant in range (bots too, so a
-- solo round can finish), eat when hungry, and keep inside the closing border.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = require(ReplicatedStorage.Shared.Combat)
local Collapse = require(ReplicatedStorage.Shared.Collapse)
local Config = require(ReplicatedStorage.Shared.Config)
local LootTable = require(ReplicatedStorage.Shared.LootTable)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local CollapseService = require(script.Parent.CollapseService)
local CombatService = require(script.Parent.CombatService)
local Entrants = require(script.Parent.Entrants)
local LootService = require(script.Parent.LootService)
local SurvivalService = require(script.Parent.SurvivalService)

local BotService = {}

local folder: Folder? = nil
local arena: ArenaBuilder.Arena? = nil
local random = Random.new()
local wanderTargets: { [Entrants.Entrant]: Vector3 } = {}

function BotService.enabled(): boolean
	if RunService:IsStudio() then
		return Config.Bots.EnabledInStudio
	end
	return Config.Bots.EnabledLive
end

-- How many bots to add to a roster of `humanCount` players.
function BotService.botsNeeded(humanCount: number): number
	if not BotService.enabled() then
		return 0
	end
	return math.max(0, math.min(Config.Bots.FillTo, Config.Queue.MaxPlayers) - humanCount)
end

-- Keeps the server simulating the bot, so no nearby player's client owns its physics.
-- Call again after unanchoring: anchoring on the server resets network ownership.
function BotService.claimPhysics(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and not root.Anchored then
		root:SetNetworkOwner(nil)
	end
end

-- Spawns bot number `index` standing at `at` and returns its model. Yields while the rig loads.
function BotService.spawn(index: number, at: CFrame): Model
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Bots"
		newFolder.Parent = workspace
		folder = newFolder
	end

	local model = Players:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = `Bot {index}`
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = model.Name
	end
	model:PivotTo(at)
	model.Parent = folder
	BotService.claimPhysics(model)
	return model
end

function BotService.despawnAll()
	if folder then
		folder:ClearAllChildren()
	end
	table.clear(wanderTargets)
end

-- Thinking ---------------------------------------------------------------------------------

local function findSlot(bot: Entrants.Entrant, matches: (string) -> boolean): number?
	for slot = 1, Config.Inventory.Slots do
		local item = LootService.itemAt(bot, slot)
		if item and matches(item) then
			return slot
		end
	end
	return nil
end

-- The slot of the weapon to use at `distance`: the hardest-hitting one that reaches, or
-- else the longest-reaching one (to close in with). Nil when the bot has no weapon.
local function chooseWeapon(bot: Entrants.Entrant, distance: number): (number?, string?)
	local bestSlot, bestItem, bestReaches, bestScore = nil, nil, false, -math.huge
	for slot = 1, Config.Inventory.Slots do
		local item = LootService.itemAt(bot, slot)
		local weapon = if item then Combat.weapon(item) else nil
		if item and weapon then
			local reaches = Combat.inRange(distance, weapon)
			local score = if reaches then weapon.Damage else weapon.Range
			if (reaches and not bestReaches) or (reaches == bestReaches and score > bestScore) then
				bestSlot, bestItem, bestReaches, bestScore = slot, item, reaches, score
			end
		end
	end
	return bestSlot, bestItem
end

local function nearestEnemy(bot: Entrants.Entrant, position: Vector3): (Entrants.Entrant?, number)
	local best: Entrants.Entrant? = nil
	local bestDistance = math.huge
	for _, entrant in Entrants.living() do
		local root = Entrants.rootPart(entrant)
		if entrant ~= bot and root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = entrant, distance
			end
		end
	end
	return best, bestDistance
end

-- Nudges a unit aim direction by up to about AimSpreadDegrees.
local function withSpread(aim: Vector3): Vector3
	local nudge = random:NextUnitVector() * math.tan(math.rad(Config.Bots.AimSpreadDegrees)) * random:NextNumber()
	return (aim + nudge).Unit
end

-- The bot's current wander spot, or a fresh random one inside `radius` once it arrives.
local function wanderTarget(bot: Entrants.Entrant, position: Vector3, center: Vector3, radius: number): Vector3
	local target = wanderTargets[bot]
	if target and (target - position).Magnitude > Config.Bots.ArriveDistance then
		return target
	end
	local angle = random:NextNumber(0, 2 * math.pi)
	local distance = random:NextNumber(0, radius)
	local fresh = center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	wanderTargets[bot] = fresh
	return fresh
end

local function think(bot: Entrants.Entrant, current: ArenaBuilder.Arena)
	local root = Entrants.rootPart(bot)
	local humanoid = Entrants.humanoid(bot)
	if not root or not humanoid or root.Anchored then
		return
	end
	local position = root.Position
	local center = current.center
	local flat = Vector3.new(position.X - center.X, 0, position.Z - center.Z)

	-- 1. Stay inside the radius the border is closing to.
	local safeRadius = math.max(0, CollapseService.targetRadius() - Config.Bots.BorderMargin)
	if flat.Magnitude > safeRadius and flat.Magnitude > 0 then
		humanoid:MoveTo(center + flat.Unit * safeRadius / 2)
		return
	end

	-- 2. Eat when hungry.
	if bot.hunger < Config.Bots.HungryBelow then
		local foodSlot = findSlot(bot, function(item)
			return LootTable.foodValue(item) ~= nil
		end)
		if foodSlot then
			SurvivalService.useItem(bot, foodSlot)
		end
	end

	-- 3. Fight whoever is closest, if armed and they're near.
	local enemy, enemyDistance = nearestEnemy(bot, position)
	local enemyRoot = if enemy then Entrants.rootPart(enemy) else nil
	local slot, item = chooseWeapon(bot, enemyDistance)
	local weapon = if item then Combat.weapon(item) else nil
	if enemyRoot and slot and item and weapon and enemyDistance <= Config.Bots.AggroRange then
		if Combat.inRange(enemyDistance, weapon) then
			local origin = position + Vector3.new(0, Config.Combat.EyeHeight, 0)
			local aim = (enemyRoot.Position - origin).Unit
			local ranged = Combat.isRanged(item)
			CombatService.attack(bot, slot, if ranged then withSpread(aim) else aim)
			humanoid:MoveTo(if ranged then position else enemyRoot.Position)
		else
			humanoid:MoveTo(enemyRoot.Position)
		end
		return
	end

	-- 4. Loot the nearest crate inside the border.
	if LootService.hasFreeSlot(bot) then
		local crate = LootService.nearestCrate(position, function(part)
			local offset = part.Position - center
			return not Collapse.isOutside(safeRadius, offset.X, offset.Z)
		end)
		if crate then
			if (crate.Position - position).Magnitude <= Config.Loot.Reach then
				LootService.openCrate(bot, crate)
			else
				humanoid:MoveTo(crate.Position)
			end
			return
		end
	end

	-- 5. Wander inside the border. The Collapse brings everyone together in the end.
	humanoid:MoveTo(wanderTarget(bot, position, center, safeRadius))
end

function BotService.onPhaseChanged(phase: string, roundArena: ArenaBuilder.Arena?)
	if phase == "Active" then
		arena = roundArena
		for _, entrant in Entrants.living() do
			if not entrant.player then
				BotService.claimPhysics(entrant.character)
			end
		end
	elseif phase == "Results" then
		arena = nil
	elseif phase == "Waiting" then
		arena = nil
		BotService.despawnAll()
	end
end

function BotService.start()
	task.spawn(function()
		while true do
			task.wait(Config.Bots.ThinkSeconds)
			local current = arena
			if current then
				for _, entrant in Entrants.living() do
					if not entrant.player then
						xpcall(think, function(message: unknown)
							warn(`{entrant.name} failed to think: {message}`)
						end, entrant, current)
					end
				end
			end
		end
	end)
end

return BotService
