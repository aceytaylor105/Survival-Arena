--!strict
-- The Entrants in the current round, players and bots alike, with their server-side health
-- and hunger. Other services read and change these records; nothing here trusts the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

export type Entrant = {
	name: string, -- unique: the player's Name, or "Bot N" (usernames can't contain spaces)
	player: Player?,
	character: Model,
	health: number,
	hunger: number,
	alive: boolean,
	attackReadyAt: number, -- os.clock() time the next attack is allowed
}

local Entrants = {}

-- Living Entrants' characters carry this tag; clients use it to pick spectate targets.
Entrants.LivingTag = "LivingEntrant"

local list: { Entrant } = {}
local byPlayer: { [Player]: Entrant } = {}
local byCharacter: { [Model]: Entrant } = {}
local diedHandler: ((Entrant) -> ())? = nil

-- Called when a living Entrant's Humanoid dies outside combat (a fall, say).
function Entrants.setDiedHandler(handler: (Entrant) -> ())
	diedHandler = handler
end

function Entrants.add(name: string, player: Player?, character: Model): Entrant
	local entrant: Entrant = {
		name = name,
		player = player,
		character = character,
		health = Config.Survival.MaxHealth,
		hunger = Config.Survival.MaxHunger,
		alive = true,
		attackReadyAt = 0,
	}
	table.insert(list, entrant)
	if player then
		byPlayer[player] = entrant
	end
	byCharacter[character] = entrant
	character:AddTag(Entrants.LivingTag)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			if entrant.alive and diedHandler then
				diedHandler(entrant)
			end
		end)
	end

	Entrants.sendStats(entrant)
	return entrant
end

function Entrants.all(): { Entrant }
	return list
end

function Entrants.living(): { Entrant }
	local living = {}
	for _, entrant in list do
		if entrant.alive then
			table.insert(living, entrant)
		end
	end
	return living
end

function Entrants.livingCount(): number
	local count = 0
	for _, entrant in list do
		if entrant.alive then
			count += 1
		end
	end
	return count
end

function Entrants.fromPlayer(player: Player): Entrant?
	return byPlayer[player]
end

-- The Entrant whose character contains `instance`, if any.
function Entrants.fromInstance(instance: Instance): Entrant?
	local node: Instance? = instance
	while node do
		if node:IsA("Model") then
			local entrant = byCharacter[node :: Model]
			if entrant then
				return entrant
			end
		end
		node = node.Parent
	end
	return nil
end

function Entrants.isPlayerAlive(player: Player): boolean
	local entrant = byPlayer[player]
	return entrant ~= nil and entrant.alive
end

function Entrants.rootPart(entrant: Entrant): BasePart?
	return entrant.character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Entrants.humanoid(entrant: Entrant): Humanoid?
	return entrant.character:FindFirstChildOfClass("Humanoid")
end

-- Anchors (or frees) the Entrant in place; used to hold everyone on their pads.
function Entrants.setFrozen(entrant: Entrant, frozen: boolean)
	local root = Entrants.rootPart(entrant)
	if root then
		root.Anchored = frozen
	end
end

-- Marks the Entrant as out. Knockout effects and broadcasts belong to CombatService.
function Entrants.markOut(entrant: Entrant)
	entrant.alive = false
	entrant.character:RemoveTag(Entrants.LivingTag)
end

function Entrants.sendStats(entrant: Entrant)
	if entrant.player then
		Remotes.statsChanged(entrant.player, entrant.health, entrant.hunger)
	end
end

function Entrants.clear()
	table.clear(list)
	table.clear(byPlayer)
	table.clear(byCharacter)
end

return Entrants
