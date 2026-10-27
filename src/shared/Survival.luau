--!strict
-- Hunger and starvation. Pure rules: no Roblox globals; elapsed time comes in as `dt`.

local Config = require("./Config")

local Survival = {}

-- Seconds for a full hunger bar to run out.
function Survival.secondsToEmpty(): number
	return Config.Survival.MaxHunger / Config.Survival.HungerDrainPerSecond
end

-- Advances hunger by `dt` seconds. Returns the new hunger and the starvation damage owed
-- for the part of `dt` spent with an empty bar.
function Survival.step(hunger: number, dt: number): (number, number)
	local drainPerSecond = Config.Survival.HungerDrainPerSecond
	local remaining = math.max(0, hunger - drainPerSecond * dt)
	local secondsUntilEmpty = if drainPerSecond > 0 then hunger / drainPerSecond else math.huge
	local starvingSeconds = math.max(0, dt - secondsUntilEmpty)
	return remaining, starvingSeconds * Config.Survival.StarvingDamagePerSecond
end

-- Hunger after eating food that restores `restores`, capped at MaxHunger.
function Survival.eat(hunger: number, restores: number): number
	return math.min(Config.Survival.MaxHunger, hunger + restores)
end

return Survival
