--!strict
-- Shows health, hunger, the phase timer, players left and a Collapse warning, plus the
-- inventory slots, a knockout feed and short banners (the Feast, knockouts, the winner).
-- Laid out for phones first: vitals top-left (the thumbstick owns the bottom-left), slots
-- bottom-center, touch buttons bottom-right.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local InputController = require(script.Parent.InputController)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function remote(name: string): RemoteEvent
	return remotes:WaitForChild(name) :: RemoteEvent
end

local player = Players.LocalPlayer
local Hud = Config.Hud

local HudController = {}

local state = {
	phase = "Waiting",
	endTime = 0,
	winner = nil :: string?,
	health = Config.Survival.MaxHealth,
	hunger = Config.Survival.MaxHunger,
	playersLeft = 0,
	targetRadius = nil :: number?,
	nextStageTime = 0,
}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function clock(seconds: number): string
	local whole = math.ceil(seconds)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- "FeastBasket" -> "Feast Basket"
local function displayName(item: string): string
	return (string.gsub(item, "(%l)(%u)", "%1 %2"))
end

local function makeLabel(parent: Instance, name: string, textSize: number, bold: boolean): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = if bold then Enum.Font.BuilderSansBold else Enum.Font.BuilderSansMedium
	label.TextSize = textSize
	label.TextColor3 = rgb(Config.Colors.Text)
	label.TextStrokeTransparency = Hud.TextStrokeTransparency
	label.Text = ""
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.new()
	label.Parent = parent
	return label
end

local function makeList(parent: Instance, name: string, direction: Enum.FillDirection, align: Enum.HorizontalAlignment): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.new()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.HorizontalAlignment = align
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, Hud.Padding / 2)
	layout.Parent = frame
	frame.Parent = parent
	return frame
end

local function makeBar(parent: Instance, name: string, color: { number }, order: number): (Frame, TextLabel)
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.LayoutOrder = order
	bar.Size = UDim2.fromOffset(Hud.BarWidth, Hud.BarHeight)
	bar.BackgroundColor3 = rgb(Config.Colors.Panel)
	bar.BackgroundTransparency = Hud.PanelTransparency
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = rgb(color)
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = bar
	local text = makeLabel(bar, "Value", Hud.SmallTextSize, true)
	text.AutomaticSize = Enum.AutomaticSize.None
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = 2
	for _, child in { bar, fill } do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Hud.CornerRadius)
		corner.Parent = child
	end
	bar.Parent = parent
	return fill, text
end

-- Built in start()
local gui: ScreenGui
local phaseLabel: TextLabel
local infoLabel: TextLabel
local warningLabel: TextLabel
local vitals: Frame
local healthFill: Frame
local healthText: TextLabel
local hungerFill: Frame
local hungerText: TextLabel
local slotRow: Frame
local slotButtons: { TextButton } = {}
local feed: Frame
local banner: TextLabel
local bannerToken = 0
local feedCount = 0

local function inRound(): boolean
	local character = player.Character
	return character ~= nil and character:HasTag(Config.Round.LivingEntrantTag)
end

local function showBanner(text: string)
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	banner.Visible = true
	task.delay(Hud.BannerSeconds, function()
		if bannerToken == token then
			banner.Visible = false
		end
	end)
end

local function addFeedLine(text: string)
	feedCount += 1
	local line = makeLabel(feed, "Line", Hud.SmallTextSize, false)
	line.LayoutOrder = -feedCount -- newest on top
	line.Text = text
	local lines = {}
	for _, child in feed:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(lines, child)
		end
	end
	table.sort(lines, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = Hud.KillFeedLines + 1, #lines do
		lines[index]:Destroy()
	end
	task.delay(Hud.KillFeedSeconds, function()
		line:Destroy()
	end)
end

local function renderStats()
	local health = math.clamp(state.health / Config.Survival.MaxHealth, 0, 1)
	local hunger = math.clamp(state.hunger / Config.Survival.MaxHunger, 0, 1)
	healthFill.Size = UDim2.fromScale(health, 1)
	hungerFill.Size = UDim2.fromScale(hunger, 1)
	healthText.Text = `Health {math.ceil(state.health)}`
	hungerText.Text = `Hunger {math.ceil(state.hunger)}`
end

local function renderSlots(items: { string }?)
	for slot, button in slotButtons do
		if items then
			local item = items[slot]
			button.Text = if item and item ~= "" then displayName(item) else ""
		end
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			local selected = slot == InputController.selectedSlot()
			stroke.Color = if selected then rgb(Config.Colors.SelectedSlot) else rgb(Config.Colors.Panel)
			stroke.Thickness = if selected then Hud.SelectedSlotStroke else Hud.SlotStroke
		end
	end
end

-- Horizontal distance from the arena center to the wall's corners, read off the wall
-- segments the server places (an inscribed polygon), or nil when there is no wall.
local function currentBorder(): (Vector3?, number?)
	local arena = workspace:FindFirstChild("Arena")
	local floor = arena and arena:FindFirstChild("Floor") :: BasePart?
	local wall = arena and arena:FindFirstChild("CollapseWall")
	local segment = wall and wall:FindFirstChildWhichIsA("BasePart")
	if not floor or not segment then
		return nil, nil
	end
	local center = Vector3.new(floor.Position.X, 0, floor.Position.Z)
	local offset = Vector3.new(segment.Position.X, 0, segment.Position.Z) - center
	return center, math.sqrt(offset.Magnitude ^ 2 + (segment.Size.X / 2) ^ 2)
end

local function refresh()
	local remaining = math.max(0, state.endTime - workspace:GetServerTimeNow())
	local phase = state.phase
	if phase == "Waiting" then
		phaseLabel.Text = if state.endTime > 0 then `Round starts in {clock(remaining)}` else "Waiting for Entrants"
	elseif phase == "Countdown" then
		phaseLabel.Text = `Get ready  {clock(remaining)}`
	elseif phase == "Active" then
		phaseLabel.Text = if remaining > 0 then `The Collapse  {clock(remaining)}` else "Final circle"
	else
		phaseLabel.Text = if state.winner then `{state.winner} wins!` else "No one survived"
	end

	local info = ""
	if phase == "Countdown" or phase == "Active" then
		info = `{state.playersLeft} left`
		if phase == "Active" and state.targetRadius then
			info ..= if state.nextStageTime > 0
				then `  ·  border closing to {math.floor(state.targetRadius)} in {clock(math.max(0, state.nextStageTime - workspace:GetServerTimeNow()))}`
				else "  ·  border holding"
		end
	end
	infoLabel.Text = info

	local playing = inRound()
	vitals.Visible = playing
	slotRow.Visible = playing
	InputController.setTouchButtonsVisible(playing and phase == "Active")

	-- Collapse warning
	warningLabel.Visible = false
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local center, radius = currentBorder()
	if playing and phase == "Active" and root and center and radius then
		local distance = (Vector3.new(root.Position.X, 0, root.Position.Z) - center).Magnitude
		if distance > radius then
			warningLabel.Text = "Outside the border! Get back inside"
			warningLabel.TextColor3 = rgb(Config.Colors.Danger)
			warningLabel.Visible = true
		elseif distance > radius - Hud.BorderWarningDistance or (state.targetRadius and distance > state.targetRadius) then
			warningLabel.Text = "The Collapse is closing in. Head for the Spire"
			warningLabel.TextColor3 = rgb(Config.Colors.Warning)
			warningLabel.Visible = true
		end
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false

	local top = makeList(gui, "Top", Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Center)
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, Hud.Padding)
	phaseLabel = makeLabel(top, "Phase", Hud.TitleTextSize, true)
	phaseLabel.LayoutOrder = 1
	infoLabel = makeLabel(top, "Info", Hud.TextSize, false)
	infoLabel.LayoutOrder = 2
	warningLabel = makeLabel(top, "Warning", Hud.TextSize, true)
	warningLabel.LayoutOrder = 3
	warningLabel.Visible = false

	vitals = makeList(gui, "Vitals", Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Left)
	vitals.Position = UDim2.fromOffset(Hud.Padding, Hud.Padding)
	healthFill, healthText = makeBar(vitals, "Health", Config.Colors.Health, 1)
	hungerFill, hungerText = makeBar(vitals, "Hunger", Config.Colors.Hunger, 2)

	slotRow = makeList(gui, "Slots", Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	slotRow.AnchorPoint = Vector2.new(0.5, 1)
	slotRow.Position = UDim2.new(0.5, 0, 1, -Hud.Padding)
	for slot = 1, Config.Inventory.Slots do
		local button = Instance.new("TextButton")
		button.Name = `Slot{slot}`
		button.LayoutOrder = slot
		button.Size = UDim2.fromOffset(Hud.SlotSize, Hud.SlotSize)
		button.BackgroundColor3 = rgb(Config.Colors.Panel)
		button.BackgroundTransparency = Hud.PanelTransparency
		button.Font = Enum.Font.BuilderSansBold
		button.TextSize = Hud.SmallTextSize
		button.TextWrapped = true
		button.TextColor3 = rgb(Config.Colors.Text)
		button.Text = ""
		local number = makeLabel(button, "Number", Hud.TinyTextSize, false)
		number.Text = tostring(slot)
		number.Position = UDim2.fromOffset(Hud.CornerRadius, 0)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, Hud.CornerRadius)
		corner.Parent = button
		button.Activated:Connect(function()
			InputController.selectSlot(slot)
		end)
		button.Parent = slotRow
		table.insert(slotButtons, button)
	end

	feed = makeList(gui, "Feed", Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right)
	feed.AnchorPoint = Vector2.new(1, 0)
	feed.Position = UDim2.new(1, -Hud.Padding, 0, Hud.Padding)

	banner = makeLabel(gui, "Banner", Hud.TitleTextSize, true)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.3)
	banner.Visible = false

	gui.Parent = player:WaitForChild("PlayerGui")
end

function HudController.start()
	build()
	renderStats()
	renderSlots(table.create(Config.Inventory.Slots, ""))
	InputController.onSlotChanged(function()
		renderSlots(nil)
	end)

	remote("PhaseChanged").OnClientEvent:Connect(function(phase: string, endTime: number, winner: string?)
		state.phase = phase
		state.endTime = endTime
		state.winner = winner
		if phase == "Countdown" then
			state.targetRadius = nil
			state.nextStageTime = 0
		elseif phase == "Results" and winner == player.Name then
			showBanner("You win!")
		end
	end)
	remote("StatsChanged").OnClientEvent:Connect(function(health: number, hunger: number)
		state.health = health
		state.hunger = hunger
		renderStats()
	end)
	remote("PlayersLeftChanged").OnClientEvent:Connect(function(count: number)
		state.playersLeft = count
	end)
	remote("CollapseChanged").OnClientEvent:Connect(function(radius: number, nextStageTime: number)
		state.targetRadius = radius
		state.nextStageTime = nextStageTime
	end)
	remote("InventoryChanged").OnClientEvent:Connect(function(items: { string })
		renderSlots(items)
	end)
	remote("FeastStarted").OnClientEvent:Connect(function()
		showBanner("The Feast is ready at the Supply Spire!")
		addFeedLine("The Feast has begun")
	end)
	remote("KnockedOut").OnClientEvent:Connect(function(victim: string, by: string?)
		addFeedLine(if by then `{by} knocked out {victim}` else `{victim} was knocked out by the arena`)
		if victim == player.Name then
			showBanner(if by then `Knocked out by {by}` else "Knocked out")
		end
	end)

	-- Keep the timer, warning and visibility current.
	task.spawn(function()
		while true do
			refresh()
			task.wait(Hud.RefreshSeconds)
		end
	end)

	-- Tags replicate, so the HUD hides the moment the server knocks us out.
	CollectionService:GetInstanceRemovedSignal(Config.Round.LivingEntrantTag):Connect(refresh)
end

return HudController
