--!strict
-- Server-side R15 bots, so one person can test a full round. Studio only by default
-- (Config.Bots); never on in a live server unless EnabledLive is turned on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Entrants = require(script.Parent.Entrants)

local BotService = {}

local folder: Folder? = nil

function BotService.enabled(): boolean
	if RunService:IsStudio() then
		return Config.Bots.EnabledInStudio
	end
	return Config.Bots.EnabledLive
end

-- How many bots to add to a roster of `humanCount` players.
function BotService.botsNeeded(humanCount: number): number
	if not BotService.enabled() then
		return 0
	end
	return math.max(0, math.min(Config.Bots.FillTo, Config.Queue.MaxPlayers) - humanCount)
end

-- Spawns bot number `index` standing at `at` and returns its model. Yields while the rig loads.
function BotService.spawn(index: number, at: CFrame): Model
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Bots"
		newFolder.Parent = workspace
		folder = newFolder
	end

	local model = Players:CreateHumanoidModelFromDescriptionAsync(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = `Bot {index}`
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = model.Name
	end
	model:PivotTo(at)
	model.Parent = folder
	BotService.claimPhysics(model)
	return model
end

-- Keeps the server simulating the bot, so no nearby player's client owns its physics.
-- Call again after unanchoring: anchoring on the server resets network ownership.
function BotService.claimPhysics(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and not root.Anchored then
		root:SetNetworkOwner(nil)
	end
end

function BotService.onPhaseChanged(phase: string)
	if phase == "Active" then
		for _, entrant in Entrants.living() do
			if not entrant.player then
				BotService.claimPhysics(entrant.character)
			end
		end
	elseif phase == "Waiting" then
		BotService.despawnAll()
	end
end

function BotService.despawnAll()
	if folder then
		folder:ClearAllChildren()
	end
end

return BotService
