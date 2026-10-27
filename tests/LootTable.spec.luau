--!strict
local Config = require("../src/shared/Config")
local LootTable = require("../src/shared/LootTable")
local T = require("./TestKit")

local ROLLS = 10000
local TOLERANCE_POINTS = 2

local function seeded(seed: number): () -> number
	math.randomseed(seed)
	return function()
		return math.random()
	end
end

local function checkDistribution(weights: LootTable.Weights, seed: number)
	local nextRoll = seeded(seed)
	local counts: { [string]: number } = {}
	for _ = 1, ROLLS do
		local tier = LootTable.rollTier(weights, nextRoll)
		counts[tier] = (counts[tier] or 0) + 1
	end
	local total = 0
	for _, weight in weights do
		total += weight
	end
	for tier, weight in weights do
		local expected = weight / total * 100
		local actual = (counts[tier] or 0) / ROLLS * 100
		T.near(actual, expected, TOLERANCE_POINTS, `{tier} share (percent)`)
	end
end

return function(test)
	test(`{ROLLS} crate rolls land within {TOLERANCE_POINTS} points of TierWeights`, function()
		checkDistribution(Config.Loot.TierWeights, 1)
		checkDistribution(Config.Loot.TierWeights, 2)
	end)

	test(`{ROLLS} Spire crate rolls land within {TOLERANCE_POINTS} points of SpireTierWeights`, function()
		checkDistribution(Config.Loot.SpireTierWeights, 3)
		checkDistribution(Config.Loot.SpireTierWeights, 4)
	end)

	test("pick walks keys in sorted order and respects the boundaries", function()
		local weights = { B = 1, A = 1, C = 2 } -- sorted: A [0, 0.25), B [0.25, 0.5), C [0.5, 1)
		T.equal(LootTable.pick(weights, 0), "A")
		T.equal(LootTable.pick(weights, 0.2499), "A")
		T.equal(LootTable.pick(weights, 0.25), "B")
		T.equal(LootTable.pick(weights, 0.5), "C")
		T.equal(LootTable.pick(weights, 0.999999), "C")
	end)

	test("zero weights are never picked", function()
		local nextRoll = seeded(5)
		for _ = 1, 1000 do
			T.equal(LootTable.pick({ Never = 0, Always = 1 }, nextRoll()), "Always")
		end
	end)

	test("crate contents come from the tier's pool, ItemsPerCrate at a time", function()
		local nextRoll = seeded(6)
		for _, tier in LootTable.Tiers do
			for _ = 1, 200 do
				local items = LootTable.rollContents(tier, nextRoll)
				T.equal(#items, Config.Loot.ItemsPerCrate[tier], `{tier} item count`)
				for _, item in items do
					T.truthy(Config.Loot.TierItems[tier][item], `{item} is in the {tier} pool`)
				end
			end
		end
	end)

	test("every loot item is a weapon or a food", function()
		for tier, pool in Config.Loot.TierItems do
			for item in pool do
				local isWeapon = LootTable.isWeapon(item)
				local isFood = LootTable.foodValue(item) ~= nil
				T.truthy(isWeapon ~= isFood, `{tier} item {item} must be exactly one of weapon or food`)
			end
		end
		T.truthy(LootTable.isWeapon("Bow"))
		T.equal(LootTable.foodValue("Bow"), nil)
		T.equal(LootTable.foodValue("Bread"), Config.Survival.FoodRestores.Bread)
	end)
end
