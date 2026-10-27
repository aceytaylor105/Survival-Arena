--!strict
-- The Collapse: border radius per stage. Pure rules: no Roblox globals.
--
-- Stage k (1..stageCount) runs for StageSeconds. During it the border shrinks linearly
-- from the radius at the end of stage k-1 to the radius at the end of stage k. Stage 0 is
-- the full arena; the last stage ends at FinalRadius, where the border then holds.

local Config = require("./Config")

local Collapse = {}

-- Radius at the end of `stage` (clamped to 0..stageCount).
function Collapse.stageRadius(arenaRadius: number, stageCount: number, stage: number): number
	local clamped = math.clamp(stage, 0, stageCount)
	local finalRadius = Config.Collapse.FinalRadius
	return arenaRadius + (finalRadius - arenaRadius) * (clamped / stageCount)
end

-- Seconds from the start of the Active phase until the border reaches FinalRadius.
function Collapse.totalSeconds(stageCount: number): number
	return stageCount * Config.Collapse.StageSeconds
end

-- The stage running `elapsed` seconds into the Active phase: 1..stageCount, or
-- stageCount + 1 once every stage has finished and the border is holding.
function Collapse.stageAt(stageCount: number, elapsed: number): number
	if elapsed < 0 then
		return 1
	end
	return math.min(math.floor(elapsed / Config.Collapse.StageSeconds) + 1, stageCount + 1)
end

-- Seconds from the start of the Active phase until `stage` ends.
function Collapse.stageEndsAt(stage: number): number
	return stage * Config.Collapse.StageSeconds
end

-- The border radius `elapsed` seconds into the Active phase.
function Collapse.radiusAt(arenaRadius: number, stageCount: number, elapsed: number): number
	local stage = Collapse.stageAt(stageCount, elapsed)
	if stage > stageCount then
		return Config.Collapse.FinalRadius
	end
	local from = Collapse.stageRadius(arenaRadius, stageCount, stage - 1)
	local to = Collapse.stageRadius(arenaRadius, stageCount, stage)
	local stageSeconds = Config.Collapse.StageSeconds
	local progress = math.clamp((elapsed - (stage - 1) * stageSeconds) / stageSeconds, 0, 1)
	return from + (to - from) * progress
end

-- True when a point at horizontal offset (dx, dz) from the arena center is outside `radius`.
function Collapse.isOutside(radius: number, dx: number, dz: number): boolean
	return dx * dx + dz * dz > radius * radius
end

return Collapse
