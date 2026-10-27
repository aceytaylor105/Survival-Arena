--!strict
-- Damage, cooldowns and range checks. Pure rules: no Roblox globals. Positions and
-- directions come in as plain { x, y, z } tables; times come in as parameters.

local Config = require("./Config")

export type Weapon = { Damage: number, Range: number, Cooldown: number }
export type Point = { x: number, y: number, z: number }

local Combat = {}

-- Weapons that shoot along the aim direction instead of striking a target in an arc.
local RANGED: { [string]: boolean } = { Bow = true }

-- Config.Weapons viewed as a lookup by weapon name (cast through unknown to widen keys).
local weapons = (Config.Weapons :: unknown) :: { [string]: Weapon }

-- The weapon's stats, or nil when `item` isn't a weapon.
function Combat.weapon(item: string): Weapon?
	return weapons[item]
end

function Combat.isRanged(item: string): boolean
	return RANGED[item] == true
end

-- True once `now` has reached the time the attacker's last attack recovers.
function Combat.isReady(now: number, readyAt: number): boolean
	return now >= readyAt
end

-- When the attacker may attack again after attacking with `weapon` at `now`.
function Combat.readyAtAfter(now: number, weapon: Weapon): number
	return now + weapon.Cooldown
end

function Combat.inRange(distance: number, weapon: Weapon): boolean
	return distance <= weapon.Range
end

-- True when `offset` points within MeleeArcDegrees of the unit `aim` direction.
function Combat.inArc(aim: Point, offset: Point): boolean
	local length = math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
	if length == 0 then
		return true
	end
	local cosine = (aim.x * offset.x + aim.y * offset.y + aim.z * offset.z) / length
	return cosine >= math.cos(math.rad(Config.Combat.MeleeArcDegrees))
end

-- Indexes of `targets` a melee swing from `origin` toward `aim` can reach: in range and in
-- the arc, nearest first. The caller still checks line of sight.
function Combat.meleeTargets(origin: Point, aim: Point, weapon: Weapon, targets: { Point }): { number }
	local hits: { { index: number, distance: number } } = {}
	for index, target in targets do
		local offset = { x = target.x - origin.x, y = target.y - origin.y, z = target.z - origin.z }
		local distance = math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
		if Combat.inRange(distance, weapon) and Combat.inArc(aim, offset) then
			table.insert(hits, { index = index, distance = distance })
		end
	end
	table.sort(hits, function(a, b)
		return a.distance < b.distance
	end)
	local indexes = {}
	for _, hit in hits do
		table.insert(indexes, hit.index)
	end
	return indexes
end

-- Health after taking `damage`, and whether that knocks the Entrant out.
function Combat.applyDamage(health: number, damage: number): (number, boolean)
	local remaining = math.max(0, health - math.max(0, damage))
	return remaining, remaining <= 0
end

-- Hits it takes to knock out an Entrant at full health.
function Combat.hitsToKnockOut(weapon: Weapon): number
	return math.ceil(Config.Survival.MaxHealth / weapon.Damage)
end

return Combat
