--!strict
local Config = require("../src/shared/Config")
local LobbySize = require("../src/shared/LobbySize")
local RoundPhases = require("../src/shared/RoundPhases")
local T = require("./TestKit")

return function(test)
	test("phases run Waiting -> Countdown -> Active -> Results -> Waiting", function()
		T.equal(RoundPhases.next("Waiting"), "Countdown")
		T.equal(RoundPhases.next("Countdown"), "Active")
		T.equal(RoundPhases.next("Active"), "Results")
		T.equal(RoundPhases.next("Results"), "Waiting")
	end)

	test("Countdown and Results use their Config lengths; Waiting has none", function()
		local size = LobbySize.get("Skirmish")
		T.equal(RoundPhases.duration("Countdown", size), Config.Round.CountdownSeconds)
		T.equal(RoundPhases.duration("Results", size), Config.Round.ResultsSeconds)
		T.equal(RoundPhases.duration("Waiting", size), nil)
	end)

	-- The spec's planned round lengths: about 9, 7.5 and 4.5 minutes plus the countdown.
	local expectedActiveMinutes = { FullArena = 9, Skirmish = 7.5, Showdown = 4.5 }
	for name, minutes in expectedActiveMinutes do
		test(`{name}: Active lasts {minutes} minutes, round adds the countdown`, function()
			local size = LobbySize.get(name :: LobbySize.SizeName)
			T.equal(RoundPhases.duration("Active", size), minutes * 60)
			T.equal(RoundPhases.roundSeconds(size), minutes * 60 + Config.Round.CountdownSeconds)
		end)
	end

	test("round is over at one Entrant or none", function()
		T.truthy(RoundPhases.isRoundOver(1))
		T.truthy(RoundPhases.isRoundOver(0))
		T.falsy(RoundPhases.isRoundOver(2))
	end)

	test("Feast is due once at FeastAtPlayersLeft or fewer", function()
		local at = Config.Round.FeastAtPlayersLeft
		T.falsy(RoundPhases.feastDue(at + 1, false))
		T.truthy(RoundPhases.feastDue(at, false))
		T.truthy(RoundPhases.feastDue(at - 1, false))
		T.falsy(RoundPhases.feastDue(at, true), "never twice")
	end)
end
