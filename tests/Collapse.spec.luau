--!strict
local Collapse = require("../src/shared/Collapse")
local Config = require("../src/shared/Config")
local LobbySize = require("../src/shared/LobbySize")
local T = require("./TestKit")

local EPSILON = 1e-9

return function(test)
	for _, name in LobbySize.Names do
		local size = LobbySize.get(name)
		local stages = size.CollapseStages
		local arena = size.ArenaRadius

		test(`{name}: starts at the arena edge`, function()
			T.near(Collapse.stageRadius(arena, stages, 0), arena, EPSILON)
			T.near(Collapse.radiusAt(arena, stages, 0), arena, EPSILON)
		end)

		test(`{name}: radius shrinks every stage and reaches FinalRadius on the last one`, function()
			local previous = Collapse.stageRadius(arena, stages, 0)
			for stage = 1, stages do
				local radius = Collapse.stageRadius(arena, stages, stage)
				T.truthy(radius < previous, `stage {stage}: {radius} should be below {previous}`)
				previous = radius
			end
			T.near(previous, Config.Collapse.FinalRadius, EPSILON, "last stage")
		end)

		test(`{name}: radius over time never grows and holds at FinalRadius`, function()
			local total = Collapse.totalSeconds(stages)
			local previous = math.huge
			for elapsed = 0, total + 120, 0.5 do
				local radius = Collapse.radiusAt(arena, stages, elapsed)
				T.truthy(radius <= previous + EPSILON, `grew at {elapsed}s`)
				previous = radius
			end
			T.near(Collapse.radiusAt(arena, stages, total), Config.Collapse.FinalRadius, EPSILON)
			T.near(Collapse.radiusAt(arena, stages, total + 600), Config.Collapse.FinalRadius, EPSILON)
		end)

		test(`{name}: each stage ends on its stage radius`, function()
			for stage = 1, stages do
				local radius = Collapse.radiusAt(arena, stages, Collapse.stageEndsAt(stage))
				T.near(radius, Collapse.stageRadius(arena, stages, stage), EPSILON, `stage {stage}`)
			end
		end)
	end

	test("stageAt counts stages from 1 and caps at stageCount + 1", function()
		local stageSeconds = Config.Collapse.StageSeconds
		T.equal(Collapse.stageAt(3, -5), 1)
		T.equal(Collapse.stageAt(3, 0), 1)
		T.equal(Collapse.stageAt(3, stageSeconds - 0.01), 1)
		T.equal(Collapse.stageAt(3, stageSeconds), 2)
		T.equal(Collapse.stageAt(3, 3 * stageSeconds - 0.01), 3)
		T.equal(Collapse.stageAt(3, 3 * stageSeconds), 4)
		T.equal(Collapse.stageAt(3, 10 * stageSeconds), 4)
	end)

	test("isOutside compares horizontal distance to the radius", function()
		T.falsy(Collapse.isOutside(100, 0, 0))
		T.falsy(Collapse.isOutside(100, 60, 80), "exactly on the border is inside")
		T.truthy(Collapse.isOutside(100, 60, 80.01))
		T.truthy(Collapse.isOutside(100, -101, 0))
	end)
end
