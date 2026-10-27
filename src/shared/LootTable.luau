--!strict
-- Weighted crate rolls. Pure rules: no Roblox globals. Randomness comes in as `nextRoll`,
-- a function returning numbers in [0, 1).

local Config = require("./Config")

export type Tier = "Common" | "Rare" | "Epic"
export type Weights = { [string]: number }

local LootTable = {}

LootTable.Tiers = table.freeze({ "Common", "Rare", "Epic" } :: { Tier })

-- Picks a key from `weights` for `roll` in [0, 1). Keys are walked in sorted order, so the
-- same roll always picks the same key. Keys with zero weight are never picked.
function LootTable.pick(weights: Weights, roll: number): string
	local keys = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	assert(#keys > 0, "no positive weights to pick from")
	table.sort(keys)

	local threshold = roll * total
	local running = 0
	for _, key in keys do
		running += weights[key]
		if threshold < running then
			return key
		end
	end
	return keys[#keys] -- only reached through floating-point rounding at roll ~ 1
end

function LootTable.rollTier(weights: Weights, nextRoll: () -> number): Tier
	return LootTable.pick(weights, nextRoll()) :: Tier
end

-- The items in a crate of `tier`.
function LootTable.rollContents(tier: Tier, nextRoll: () -> number): { string }
	local items = {}
	for _ = 1, Config.Loot.ItemsPerCrate[tier] do
		table.insert(items, LootTable.pick(Config.Loot.TierItems[tier], nextRoll()))
	end
	return items
end

function LootTable.isWeapon(item: string): boolean
	return (Config.Weapons :: { [string]: unknown })[item] ~= nil
end

-- Hunger restored by eating `item`, or nil when it isn't food.
function LootTable.foodValue(item: string): number?
	return (Config.Survival.FoodRestores :: { [string]: number })[item]
end

return table.freeze(LootTable)
