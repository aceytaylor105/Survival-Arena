--!strict
-- Round phase order and timing. Pure rules: no Roblox globals.

local Collapse = require("./Collapse")
local Config = require("./Config")
local LobbySize = require("./LobbySize")

export type Phase = "Waiting" | "Countdown" | "Active" | "Results"

local RoundPhases = {}

RoundPhases.Order = table.freeze({ "Waiting", "Countdown", "Active", "Results" } :: { Phase })

-- The phase after `phase`; Results loops back to Waiting.
function RoundPhases.next(phase: Phase): Phase
	local index = table.find(RoundPhases.Order, phase)
	assert(index, `unknown phase {phase}`)
	return RoundPhases.Order[index % #RoundPhases.Order + 1]
end

-- Planned length of a phase in seconds, or nil when the phase has no fixed length
-- (Waiting ends when the queue does). Active is planned to last until the border reaches
-- FinalRadius; it actually ends whenever one Entrant is left.
function RoundPhases.duration(phase: Phase, size: LobbySize.Size): number?
	if phase == "Countdown" then
		return Config.Round.CountdownSeconds
	elseif phase == "Active" then
		return Collapse.totalSeconds(size.CollapseStages)
	elseif phase == "Results" then
		return Config.Round.ResultsSeconds
	end
	return nil
end

-- Planned seconds from the start of Countdown to the border reaching FinalRadius.
function RoundPhases.roundSeconds(size: LobbySize.Size): number
	return Config.Round.CountdownSeconds + Collapse.totalSeconds(size.CollapseStages)
end

-- The Active phase ends when one Entrant (or none) is left.
function RoundPhases.isRoundOver(aliveCount: number): boolean
	return aliveCount <= 1
end

-- The Feast happens once, as soon as FeastAtPlayersLeft or fewer Entrants remain.
function RoundPhases.feastDue(aliveCount: number, feastHeld: boolean): boolean
	return not feastHeld and aliveCount <= Config.Round.FeastAtPlayersLeft
end

return table.freeze(RoundPhases)
