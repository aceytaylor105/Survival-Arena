--!strict
-- After a knockout, cycles the camera between living Entrants until the player respawns
-- in the lobby. Big on-screen arrows for touch; arrow keys, Q/E and the D-pad otherwise.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local knockedOut = remotes:WaitForChild("KnockedOut") :: RemoteEvent
local phaseChanged = remotes:WaitForChild("PhaseChanged") :: RemoteEvent

local player = Players.LocalPlayer
local Hud = Config.Hud

local SpectateController = {}

local spectating = false
local index = 1
local gui: ScreenGui
local nameLabel: TextLabel

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function targets(): { Model }
	local list: { Model } = {}
	for _, instance in CollectionService:GetTagged(Config.Round.LivingEntrantTag) do
		if instance:IsA("Model") and instance ~= player.Character then
			table.insert(list, instance)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function show()
	local list = targets()
	if #list == 0 then
		nameLabel.Text = "No one left to watch"
		return
	end
	index = (index - 1) % #list + 1
	local target = list[index]
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if humanoid and camera then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
	local name = if humanoid and humanoid.DisplayName ~= "" then humanoid.DisplayName else target.Name
	nameLabel.Text = `Spectating {name}`
end

local function step(by: number)
	if spectating then
		index += by
		show()
	end
end

function SpectateController.begin()
	spectating = true
	index = 1
	gui.Enabled = true
	show()
end

function SpectateController.stop()
	spectating = false
	gui.Enabled = false
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local camera = workspace.CurrentCamera
	if humanoid and camera then
		camera.CameraSubject = humanoid
	end
end

local function makeArrow(parent: Instance, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = text
	button.Text = text
	button.LayoutOrder = order
	button.Font = Enum.Font.BuilderSansBold
	button.TextSize = Hud.TitleTextSize
	button.TextColor3 = rgb(Config.Colors.Text)
	button.BackgroundColor3 = rgb(Config.Colors.Panel)
	button.BackgroundTransparency = Hud.PanelTransparency
	button.Size = UDim2.fromOffset(Hud.SpectateButtonSize, Hud.SpectateButtonSize)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Hud.CornerRadius)
	corner.Parent = button
	button.Parent = parent
	return button
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Spectate"
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundTransparency = 1
	bar.AutomaticSize = Enum.AutomaticSize.XY
	bar.Size = UDim2.new()
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -Hud.Padding * 2)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Hud.Padding)
	layout.Parent = bar

	makeArrow(bar, "<", 1).Activated:Connect(function()
		step(-1)
	end)
	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Target"
	nameLabel.LayoutOrder = 2
	nameLabel.BackgroundTransparency = 1
	nameLabel.AutomaticSize = Enum.AutomaticSize.XY
	nameLabel.Size = UDim2.new()
	nameLabel.Font = Enum.Font.BuilderSansBold
	nameLabel.TextSize = Hud.TextSize
	nameLabel.TextColor3 = rgb(Config.Colors.Text)
	nameLabel.TextStrokeTransparency = Hud.TextStrokeTransparency
	nameLabel.Parent = bar
	makeArrow(bar, ">", 3).Activated:Connect(function()
		step(1)
	end)

	bar.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

function SpectateController.start()
	build()

	knockedOut.OnClientEvent:Connect(function(victim: string)
		if victim == player.Name then
			SpectateController.begin()
		elseif spectating then
			show()
		end
	end)
	phaseChanged.OnClientEvent:Connect(function(phase: string)
		if phase == "Waiting" and spectating then
			SpectateController.stop()
		end
	end)
	-- Whoever we were watching may have just been knocked out.
	CollectionService:GetInstanceRemovedSignal(Config.Round.LivingEntrantTag):Connect(function()
		if spectating then
			show()
		end
	end)
	player.CharacterAdded:Connect(function()
		if spectating then
			SpectateController.stop()
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not spectating then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Left or key == Enum.KeyCode.Q or key == Enum.KeyCode.DPadLeft then
			step(-1)
		elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.E or key == Enum.KeyCode.DPadRight then
			step(1)
		end
	end)
end

return SpectateController
