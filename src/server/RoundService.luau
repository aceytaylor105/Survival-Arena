--!strict
-- Runs the round loop: Waiting -> Countdown -> Active -> Results -> Waiting. Every other
-- server module reacts to its phase changes through RoundService.onPhaseChanged.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbySize = require(ReplicatedStorage.Shared.LobbySize)
local RoundPhases = require(ReplicatedStorage.Shared.RoundPhases)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local BotService = require(script.Parent.BotService)
local Entrants = require(script.Parent.Entrants)
local LootService = require(script.Parent.LootService)
local QueueService = require(script.Parent.QueueService)
local Remotes = require(script.Parent.Remotes)

export type Round = {
	phase: RoundPhases.Phase,
	endTime: number, -- server time the phase is planned to end; 0 = no timer
	winnerName: string?,
	arena: ArenaBuilder.Arena?,
	activeStartedAt: number, -- server time the Active phase began
	feastHeld: boolean,
}

type PhaseListener = (phase: RoundPhases.Phase, round: Round) -> ()

local RoundService = {}

local listeners: { PhaseListener } = {}
local random = Random.new()
local round: Round = {
	phase = "Waiting",
	endTime = 0,
	winnerName = nil,
	arena = nil,
	activeStartedAt = 0,
	feastHeld = false,
}

function RoundService.onPhaseChanged(listener: PhaseListener)
	table.insert(listeners, listener)
end

function RoundService.current(): Round
	return round
end

local function setPhase(phase: RoundPhases.Phase, endTime: number, winnerName: string?)
	round.phase = phase
	round.endTime = endTime
	round.winnerName = winnerName
	Remotes.phaseChanged(phase, endTime, winnerName)
	for _, listener in listeners do
		-- A failing listener reports its error without stopping the loop.
		task.spawn(listener, phase, round)
	end
end

local function spawnInLobby(player: Player)
	if not player.Parent then
		return
	end
	player:LoadCharacterAsync()
	local character = player.Character
	if character and player.Parent then
		character:PivotTo(ArenaBuilder.lobbySpawn(random))
	end
end

local function placeOnPad(player: Player, pad: CFrame): Model?
	player:LoadCharacterAsync()
	local character = player.Character
	if not character or not player.Parent then
		return nil
	end
	character:PivotTo(pad)
	return character
end

-- True while `player` is an Entrant in a round that is under way (alive or spectating).
local function inRound(player: Player): boolean
	return Entrants.fromPlayer(player) ~= nil and (round.phase == "Countdown" or round.phase == "Active")
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		-- Entrants are handled by their own Died handler; lobby players just respawn.
		if inRound(player) then
			return
		end
		task.wait(Config.Lobby.RespawnSeconds)
		if player.Character == character and not inRound(player) then
			spawnInLobby(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	-- Bring the newcomer's HUD up to date, then put them in the lobby.
	Remotes.phaseChanged(round.phase, round.endTime, round.winnerName, player)
	Remotes.playersLeftChanged(Entrants.livingCount(), player)
	spawnInLobby(player)
end

local function runRound()
	-- Waiting
	setPhase("Waiting", 0)
	local roster = QueueService.waitForRoster(BotService.enabled(), function(endsAt)
		round.endTime = endsAt or 0
		Remotes.phaseChanged("Waiting", round.endTime)
	end)

	-- Countdown: build the arena, put everyone on a pad and hold them there.
	local botCount = BotService.botsNeeded(#roster)
	local sizeName: LobbySize.SizeName? = LobbySize.pick(#roster + botCount)
	if not sizeName then
		return -- not enough players any more; back to Waiting
	end
	local arena = ArenaBuilder.build(sizeName, #roster + botCount, random:NextInteger(1, 2 ^ 31 - 1))
	round.arena = arena
	round.feastHeld = false
	Entrants.clear()

	local padIndex = 0
	for _, player in roster do
		padIndex += 1
		local character = placeOnPad(player, arena.pads[padIndex])
		if character then
			Entrants.add(player.Name, player, character)
		end
	end
	for index = 1, botCount do
		padIndex += 1
		local model = BotService.spawn(index, arena.pads[padIndex])
		Entrants.add(model.Name, nil, model)
	end
	for _, entrant in Entrants.living() do
		Entrants.setFrozen(entrant, true)
	end

	setPhase("Countdown", workspace:GetServerTimeNow() + Config.Round.CountdownSeconds)
	task.wait(Config.Round.CountdownSeconds)

	-- Active: runs until one Entrant (or none) is left. The Feast happens once, as soon as
	-- FeastAtPlayersLeft or fewer remain.
	for _, entrant in Entrants.living() do
		Entrants.setFrozen(entrant, false)
	end
	round.activeStartedAt = workspace:GetServerTimeNow()
	setPhase("Active", round.activeStartedAt + (RoundPhases.duration("Active", arena.size) or 0))
	Remotes.playersLeftChanged(Entrants.livingCount())
	while not RoundPhases.isRoundOver(Entrants.livingCount()) do
		if RoundPhases.feastDue(Entrants.livingCount(), round.feastHeld) then
			round.feastHeld = true
			LootService.startFeast(arena)
		end
		task.wait(Config.Round.CheckSeconds)
	end

	-- Results
	local winner = Entrants.living()[1]
	setPhase("Results", workspace:GetServerTimeNow() + Config.Round.ResultsSeconds, winner and winner.name)
	task.wait(Config.Round.ResultsSeconds)
end

-- Back to a clean lobby: no arena, no Entrants, everyone respawned on the platform.
local function resetToLobby()
	ArenaBuilder.clear()
	Entrants.clear()
	round.arena = nil
	for _, player in Players:GetPlayers() do
		task.spawn(spawnInLobby, player)
	end
end

-- Called when an Entrant leaves the server mid-round.
local leaveHandler: ((Entrants.Entrant) -> ())? = nil

function RoundService.setLeaveHandler(handler: (Entrants.Entrant) -> ())
	leaveHandler = handler
end

function RoundService.start()
	ArenaBuilder.buildLobby()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local entrant = Entrants.fromPlayer(player)
		if entrant and entrant.alive and leaveHandler then
			leaveHandler(entrant)
		end
	end)

	task.spawn(function()
		while true do
			xpcall(runRound, function(message: unknown)
				warn(`Round failed, returning to the lobby: {message}\n{debug.traceback()}`)
			end)
			if round.phase ~= "Waiting" then
				resetToLobby()
			end
		end
	end)
end

return RoundService
