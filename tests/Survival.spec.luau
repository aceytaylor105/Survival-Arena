--!strict
local Config = require("../src/shared/Config")
local Survival = require("../src/shared/Survival")
local T = require("./TestKit")

local TOLERANCE_SECONDS = 5

-- Steps hunger from full in ticks drawn from `nextDt` until it is empty; returns the time.
local function timeToEmpty(nextDt: () -> number): number
	local hunger = Config.Survival.MaxHunger
	local elapsed = 0
	while hunger > 0 do
		local dt = nextDt()
		hunger = Survival.step(hunger, dt)
		elapsed += dt
	end
	return elapsed
end

return function(test)
	test("Config predicts about 6.7 minutes to empty", function()
		T.near(Survival.secondsToEmpty(), 400, 1e-9)
	end)

	test(`hunger empties within {TOLERANCE_SECONDS}s of the prediction at the server tick`, function()
		local elapsed = timeToEmpty(function()
			return Config.Survival.TickSeconds
		end)
		T.near(elapsed, Survival.secondsToEmpty(), TOLERANCE_SECONDS)
	end)

	test(`hunger empties within {TOLERANCE_SECONDS}s of the prediction with uneven frames`, function()
		math.randomseed(7)
		local elapsed = timeToEmpty(function()
			return 1 / 60 + math.random() * 0.05 -- 60 fps with hitches
		end)
		T.near(elapsed, Survival.secondsToEmpty(), TOLERANCE_SECONDS)
	end)

	test("no starvation damage while there is hunger left", function()
		local hunger, damage = Survival.step(50, 10)
		T.near(hunger, 50 - 10 * Config.Survival.HungerDrainPerSecond, 1e-9)
		T.equal(damage, 0)
	end)

	test("starvation only counts the time spent empty", function()
		local drain = Config.Survival.HungerDrainPerSecond
		local hunger, damage = Survival.step(drain * 2, 5) -- empty after 2s, starving for 3s
		T.equal(hunger, 0)
		T.near(damage, 3 * Config.Survival.StarvingDamagePerSecond, 1e-9)
		hunger, damage = Survival.step(0, 10)
		T.equal(hunger, 0)
		T.near(damage, 10 * Config.Survival.StarvingDamagePerSecond, 1e-9)
	end)

	test("eating restores hunger up to MaxHunger", function()
		T.equal(Survival.eat(10, Config.Survival.FoodRestores.Bread), 10 + Config.Survival.FoodRestores.Bread)
		T.equal(Survival.eat(90, Config.Survival.FoodRestores.FeastBasket), Config.Survival.MaxHunger)
	end)
end
