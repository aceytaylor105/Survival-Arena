--!strict
-- The lobby queue. Starts the WaitSeconds timer once MinPlayers are in the lobby, cancels it
-- if the lobby drops below that, starts at once at MaxPlayers, and hands the roster over.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local QueueService = {}

-- With bots on, bots will fill the empty pads up to FillTo, so one person counts as that
-- many and a solo tester can start a round.
local function queuedCount(botsOn: boolean): number
	local count = #Players:GetPlayers()
	if botsOn and count >= 1 then
		return math.max(count, Config.Bots.FillTo)
	end
	return count
end

-- Yields until the round should start, then returns the roster (at most MaxPlayers).
-- `onTimer` gets the timer's end time when it starts, and nil when it is cancelled.
function QueueService.waitForRoster(botsOn: boolean, onTimer: (endsAt: number?) -> ()): { Player }
	local endsAt: number? = nil
	while true do
		local count = queuedCount(botsOn)
		if count >= Config.Queue.MaxPlayers then
			break
		elseif count >= Config.Queue.MinPlayers then
			local now = workspace:GetServerTimeNow()
			if not endsAt then
				endsAt = now + Config.Queue.WaitSeconds
				onTimer(endsAt)
			elseif now >= endsAt then
				break
			end
		elseif endsAt then
			endsAt = nil
			onTimer(nil)
		end
		task.wait(Config.Queue.CheckSeconds)
	end

	local roster = {}
	for _, player in Players:GetPlayers() do
		if #roster >= Config.Queue.MaxPlayers then
			break
		end
		table.insert(roster, player)
	end
	return roster
end

return QueueService
