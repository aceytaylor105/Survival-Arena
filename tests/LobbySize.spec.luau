--!strict
local Config = require("../src/shared/Config")
local LobbySize = require("../src/shared/LobbySize")
local T = require("./TestKit")

return function(test)
	local cases: { { count: number, expected: string? } } = {
		{ count = 1, expected = nil },
		{ count = 2, expected = "Showdown" },
		{ count = 5, expected = "Showdown" },
		{ count = 6, expected = "Skirmish" },
		{ count = 11, expected = "Skirmish" },
		{ count = 12, expected = "FullArena" },
		{ count = 24, expected = "FullArena" },
		{ count = 25, expected = nil },
	}

	for _, case in cases do
		test(`{case.count} players -> {case.expected or "no round"}`, function()
			local name, size = LobbySize.pick(case.count)
			T.equal(name, case.expected)
			if case.expected then
				T.equal(size, LobbySize.get(name :: LobbySize.SizeName), "size table matches Config")
			else
				T.equal(size, nil)
			end
		end)
	end

	test("rejects zero, negative, fractional and NaN counts", function()
		for _, count in { 0, -3, 2.5, 0 / 0, math.huge } do
			T.equal(LobbySize.pick(count), nil, `count {count}`)
		end
	end)

	test("every queue count from MinPlayers to MaxPlayers maps to exactly one size", function()
		for count = Config.Queue.MinPlayers, Config.Queue.MaxPlayers do
			local matches = 0
			for _, name in LobbySize.Names do
				local size = LobbySize.get(name)
				if count >= size.MinPlayers and count <= size.MaxPlayers then
					matches += 1
				end
			end
			T.equal(matches, 1, `count {count}`)
			T.truthy(LobbySize.pick(count), `count {count} picks a size`)
		end
	end)

	test("Config is frozen", function()
		T.truthy(table.isfrozen(Config))
		T.falsy(pcall(function()
			-- any: deliberately writing past the frozen type to prove the write fails
			(Config :: any).Queue = nil
		end), "writing to Config errors")
	end)
end
