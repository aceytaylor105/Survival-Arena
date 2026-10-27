--!strict
local Combat = require("../src/shared/Combat")
local Config = require("../src/shared/Config")
local T = require("./TestKit")

local WEAPONS = { "Spear", "Axe", "Bow" }

local function point(x: number, y: number, z: number): Combat.Point
	return { x = x, y = y, z = z }
end

return function(test)
	for _, name in WEAPONS do
		local weapon = Combat.weapon(name) :: Combat.Weapon

		test(`{name}: attacks before the cooldown ends are refused`, function()
			local readyAt = Combat.readyAtAfter(10, weapon)
			T.equal(readyAt, 10 + weapon.Cooldown)
			T.falsy(Combat.isReady(10, readyAt), "same instant")
			T.falsy(Combat.isReady(10 + weapon.Cooldown * 0.5, readyAt), "half way")
			T.falsy(Combat.isReady(10 + weapon.Cooldown - 0.001, readyAt), "just before")
			T.truthy(Combat.isReady(10 + weapon.Cooldown, readyAt), "exactly at the cooldown")
			T.truthy(Combat.isReady(10 + weapon.Cooldown + 5, readyAt), "long after")
		end)

		test(`{name}: reaches exactly its Range and no further`, function()
			T.truthy(Combat.inRange(0, weapon))
			T.truthy(Combat.inRange(weapon.Range, weapon))
			T.falsy(Combat.inRange(weapon.Range + 0.01, weapon))
		end)

		test(`{name}: knocks out a full-health Entrant in the expected number of hits`, function()
			local health = Config.Survival.MaxHealth
			local hits = 0
			local out = false
			while not out do
				health, out = Combat.applyDamage(health, weapon.Damage)
				hits += 1
			end
			T.equal(hits, Combat.hitsToKnockOut(weapon))
			T.equal(health, 0)
		end)
	end

	test("weapon lookups", function()
		T.equal(Combat.weapon("Bread"), nil)
		T.truthy(Combat.isRanged("Bow"))
		T.falsy(Combat.isRanged("Spear"))
		T.falsy(Combat.isRanged("Axe"))
	end)

	test("damage never heals and health never drops below zero", function()
		local health, out = Combat.applyDamage(50, -20)
		T.equal(health, 50)
		T.falsy(out)
		health, out = Combat.applyDamage(10, 35)
		T.equal(health, 0)
		T.truthy(out)
	end)

	test("melee arc: ahead hits, beside and behind miss", function()
		local aim = point(0, 0, -1)
		T.truthy(Combat.inArc(aim, point(0, 0, -5)), "straight ahead")
		local inside = math.rad(Config.Combat.MeleeArcDegrees - 5)
		local outside = math.rad(Config.Combat.MeleeArcDegrees + 5)
		T.truthy(Combat.inArc(aim, point(math.sin(inside), 0, -math.cos(inside))), "just inside the arc")
		T.falsy(Combat.inArc(aim, point(math.sin(outside), 0, -math.cos(outside))), "just outside the arc")
		T.falsy(Combat.inArc(aim, point(0, 0, 5)), "behind")
	end)

	test("meleeTargets keeps targets in range and arc, nearest first", function()
		local axe = Combat.weapon("Axe") :: Combat.Weapon
		local origin = point(0, 0, 0)
		local aim = point(0, 0, -1)
		local targets = {
			point(0, 0, -6), -- 1: in range, ahead
			point(0, 0, -3), -- 2: nearer, ahead
			point(0, 0, -(axe.Range + 1)), -- 3: out of range
			point(0, 0, 3), -- 4: behind
			point(2, 0, -2), -- 5: 45 degrees off, in range
		}
		local hits = Combat.meleeTargets(origin, aim, axe, targets)
		T.equal(#hits, 3)
		T.equal(hits[1], 5) -- distance ~2.83
		T.equal(hits[2], 2) -- 3
		T.equal(hits[3], 1) -- 6
	end)
end
