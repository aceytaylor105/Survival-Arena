--!strict
-- Creates every remote, checks every argument's type and value, and rate-limits each player
-- per remote. Request handlers only ever see validated arguments from living Entrants.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = {}

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function create(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

-- Client -> server
local requestAttack = create("RequestAttack") -- weapon slot, aim direction
local requestUseItem = create("RequestUseItem") -- inventory slot
-- Server -> clients
local phaseChanged = create("PhaseChanged") -- phase name, end time (0 = none), winner name?
local statsChanged = create("StatsChanged") -- health, hunger
local playersLeftChanged = create("PlayersLeftChanged") -- count
local collapseChanged = create("CollapseChanged") -- radius, next stage time (0 = holding)
local knockedOut = create("KnockedOut") -- who was knocked out, by whom (nil = the arena)
local inventoryChanged = create("InventoryChanged") -- item name per slot ("" = empty)
local feastStarted = create("FeastStarted")

-- Parent last, so a client that sees the folder sees every remote in it.
folder.Parent = ReplicatedStorage

-- Validation ------------------------------------------------------------------------------

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function isSlot(value: unknown): boolean
	if not isFiniteNumber(value) then
		return false
	end
	local slot = value :: number
	return slot % 1 == 0 and slot >= 1 and slot <= Config.Inventory.Slots
end

local function isUnitVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return isFiniteNumber(vector.X)
		and isFiniteNumber(vector.Y)
		and isFiniteNumber(vector.Z)
		and math.abs(vector.Magnitude - 1) <= Config.Remotes.AimTolerance
end

-- Per-player, per-remote limit over one-second windows. Excess requests are dropped silently.
local function makeLimiter(): (Player) -> boolean
	local windows: { [Player]: { startedAt: number, count: number } } = {}
	Players.PlayerRemoving:Connect(function(player)
		windows[player] = nil
	end)
	return function(player: Player): boolean
		local now = os.clock()
		local window = windows[player]
		if not window or now - window.startedAt >= 1 then
			window = { startedAt = now, count = 0 }
			windows[player] = window
		end
		window.count += 1
		return window.count <= Config.Remotes.MaxRequestsPerSecond
	end
end

-- Set by the server's wiring: true only for players who are living Entrants.
local isAlive: (Player) -> boolean = function(_player: Player)
	return false
end

function Remotes.setAliveCheck(check: (Player) -> boolean)
	isAlive = check
end

-- Requests ---------------------------------------------------------------------------------

type AttackHandler = (player: Player, slot: number, aim: Vector3) -> ()
type UseItemHandler = (player: Player, slot: number) -> ()

local attackHandler: AttackHandler? = nil
local useItemHandler: UseItemHandler? = nil

function Remotes.onRequestAttack(handler: AttackHandler)
	attackHandler = handler
end

function Remotes.onRequestUseItem(handler: UseItemHandler)
	useItemHandler = handler
end

local attackLimiter = makeLimiter()
requestAttack.OnServerEvent:Connect(function(player: Player, slot: unknown, aim: unknown)
	if not attackLimiter(player) or not isAlive(player) then
		return
	end
	if not isSlot(slot) or not isUnitVector(aim) then
		return
	end
	if attackHandler then
		attackHandler(player, slot :: number, aim :: Vector3)
	end
end)

local useItemLimiter = makeLimiter()
requestUseItem.OnServerEvent:Connect(function(player: Player, slot: unknown)
	if not useItemLimiter(player) or not isAlive(player) then
		return
	end
	if not isSlot(slot) then
		return
	end
	if useItemHandler then
		useItemHandler(player, slot :: number)
	end
end)

-- Broadcasts -------------------------------------------------------------------------------

function Remotes.phaseChanged(phase: string, endTime: number, winnerName: string?, player: Player?)
	if player then
		phaseChanged:FireClient(player, phase, endTime, winnerName)
	else
		phaseChanged:FireAllClients(phase, endTime, winnerName)
	end
end

function Remotes.statsChanged(player: Player, health: number, hunger: number)
	statsChanged:FireClient(player, health, hunger)
end

function Remotes.playersLeftChanged(count: number, player: Player?)
	if player then
		playersLeftChanged:FireClient(player, count)
	else
		playersLeftChanged:FireAllClients(count)
	end
end

function Remotes.collapseChanged(radius: number, nextStageTime: number)
	collapseChanged:FireAllClients(radius, nextStageTime)
end

function Remotes.knockedOut(victimName: string, byName: string?)
	knockedOut:FireAllClients(victimName, byName)
end

function Remotes.inventoryChanged(player: Player, items: { string })
	inventoryChanged:FireClient(player, items)
end

function Remotes.feastStarted()
	feastStarted:FireAllClients()
end

return Remotes
