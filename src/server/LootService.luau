--!strict
-- Crates and inventories. Rolls crate contents with LootTable and a seeded Random, opens
-- crates through a server-side ProximityPrompt, and holds every inventory on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LootTable = require(ReplicatedStorage.Shared.LootTable)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local Entrants = require(script.Parent.Entrants)
local Remotes = require(script.Parent.Remotes)

type Crate = {
	part: BasePart,
	tier: LootTable.Tier,
	items: { string },
	prompt: ProximityPrompt,
}

local LootService = {}

local EMPTY = "" -- an empty inventory slot

local crates: { [BasePart]: Crate } = {}
local inventories: { [Entrants.Entrant]: { string } } = {}
local random = Random.new()
local cratesOpen = false

local tierColors: { [LootTable.Tier]: { number } } = {
	Common = Config.Colors.CommonCrate,
	Rare = Config.Colors.RareCrate,
	Epic = Config.Colors.EpicCrate,
}

local function nextRoll(): number
	return random:NextNumber()
end

-- Inventories ------------------------------------------------------------------------------

function LootService.inventory(entrant: Entrants.Entrant): { string }
	local inventory = inventories[entrant]
	if not inventory then
		inventory = table.create(Config.Inventory.Slots, EMPTY)
		inventories[entrant] = inventory
	end
	return inventory
end

local function sendInventory(entrant: Entrants.Entrant)
	if entrant.player then
		Remotes.inventoryChanged(entrant.player, LootService.inventory(entrant))
	end
end

-- The item in `slot`, or nil when the slot is empty.
function LootService.itemAt(entrant: Entrants.Entrant, slot: number): string?
	local item = LootService.inventory(entrant)[slot]
	if item == nil or item == EMPTY then
		return nil
	end
	return item
end

-- Removes and returns the item in `slot`.
function LootService.takeItem(entrant: Entrants.Entrant, slot: number): string?
	local item = LootService.itemAt(entrant, slot)
	if item then
		LootService.inventory(entrant)[slot] = EMPTY
		sendInventory(entrant)
	end
	return item
end

function LootService.hasFreeSlot(entrant: Entrants.Entrant): boolean
	return table.find(LootService.inventory(entrant), EMPTY) ~= nil
end

local function addItem(inventory: { string }, item: string): boolean
	local slot = table.find(inventory, EMPTY)
	if not slot then
		return false
	end
	inventory[slot] = item
	return true
end

-- Crates -----------------------------------------------------------------------------------

-- Gives a crate part its tier, contents, color and prompt. `tier` forces the tier (the Feast).
function LootService.stockCrate(part: BasePart, tier: LootTable.Tier?)
	local weights = if part:GetAttribute("AtSpire") then Config.Loot.SpireTierWeights else Config.Loot.TierWeights
	local crateTier: LootTable.Tier = tier or LootTable.rollTier(weights, nextRoll)
	local color = tierColors[crateTier]
	part.Color = Color3.fromRGB(color[1], color[2], color[3])
	part:SetAttribute("Tier", crateTier)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = `{crateTier} crate`
	prompt.HoldDuration = Config.Loot.OpenSeconds
	prompt.MaxActivationDistance = Config.Loot.Reach
	prompt.RequiresLineOfSight = false
	prompt.Enabled = cratesOpen
	prompt.Triggered:Connect(function(player: Player)
		local entrant = Entrants.fromPlayer(player)
		if entrant then
			LootService.openCrate(entrant, part)
		end
	end)
	prompt.Parent = part

	crates[part] = {
		part = part,
		tier = crateTier,
		items = LootTable.rollContents(crateTier, nextRoll),
		prompt = prompt,
	}
end

-- Moves a crate's items into the Entrant's inventory. Items that don't fit stay in the
-- crate; an emptied crate disappears. Returns true if the crate was opened.
function LootService.openCrate(entrant: Entrants.Entrant, part: BasePart): boolean
	local crate = crates[part]
	local root = Entrants.rootPart(entrant)
	if not cratesOpen or not crate or not entrant.alive or not root then
		return false
	end
	if (root.Position - part.Position).Magnitude > Config.Loot.Reach + Config.Loot.ReachSlack then
		return false
	end

	local inventory = LootService.inventory(entrant)
	local remaining = {}
	for _, item in crate.items do
		if not addItem(inventory, item) then
			table.insert(remaining, item)
		end
	end
	crate.items = remaining
	sendInventory(entrant)

	if #remaining == 0 then
		crates[part] = nil
		part:Destroy()
	end
	return true
end

-- The closest unopened crate to `position` that `accept` allows, if any are left.
function LootService.nearestCrate(position: Vector3, accept: ((BasePart) -> boolean)?): BasePart?
	local best: BasePart? = nil
	local bestDistance = math.huge
	for part in crates do
		local distance = (part.Position - position).Magnitude
		if distance < bestDistance and (not accept or accept(part)) then
			best, bestDistance = part, distance
		end
	end
	return best
end

-- The Feast: epic crates on a ring around the Supply Spire, once per round.
function LootService.startFeast(arena: ArenaBuilder.Arena)
	local parent = arena.model:FindFirstChild("Crates") or arena.model
	local count = Config.Loot.FeastCrates
	for _, point in ArenaBuilder.spireRing(count, 3, math.pi / count) do
		LootService.stockCrate(ArenaBuilder.makeCrate(point, true, parent), "Epic")
	end
	Remotes.feastStarted()
end

local function setCratesOpen(open: boolean)
	cratesOpen = open
	for _, crate in crates do
		crate.prompt.Enabled = open
	end
end

local function clearAll()
	setCratesOpen(false)
	table.clear(crates)
	for entrant in inventories do
		if entrant.player then
			Remotes.inventoryChanged(entrant.player, table.create(Config.Inventory.Slots, EMPTY))
		end
	end
	table.clear(inventories)
end

-- Phase reactions: stock the arena's crates at Countdown, open them for the Active phase,
-- and drop every crate and inventory once the round is over.
function LootService.onPhaseChanged(phase: string, arena: ArenaBuilder.Arena?)
	if phase == "Countdown" and arena then
		clearAll()
		random = Random.new(arena.seed)
		for _, part in arena.crates do
			LootService.stockCrate(part)
		end
		for _, entrant in Entrants.all() do
			sendInventory(entrant)
		end
	elseif phase == "Active" then
		setCratesOpen(true)
	elseif phase == "Results" then
		setCratesOpen(false)
	elseif phase == "Waiting" then
		clearAll()
	end
end

return LootService
