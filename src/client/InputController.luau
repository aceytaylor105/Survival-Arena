--!strict
-- Maps keyboard, touch buttons and gamepad to attack, use item, sprint and slot selection.
-- The client only sends intent: which slot, and which way the player is aiming.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestAttack = remotes:WaitForChild("RequestAttack") :: RemoteEvent
local requestUseItem = remotes:WaitForChild("RequestUseItem") :: RemoteEvent

local player = Players.LocalPlayer

local InputController = {}

local selected = 1
local sprinting = false
local slotListeners: { (slot: number) -> () } = {}
local touchGui: ScreenGui? = nil

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
}

local function isMouseInput(inputType: Enum.UserInputType): boolean
	return inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.Keyboard
end

local function rootPart(): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Unit direction from where the server starts attacks (just above the root part) to the
-- point under the cursor, or under the screen center on touch and gamepad.
local function aimDirection(): Vector3?
	local root = rootPart()
	local camera = workspace.CurrentCamera
	local character = player.Character
	if not root or not camera or not character then
		return nil
	end
	local screenPoint = if isMouseInput(UserInputService:GetLastInputType())
		then UserInputService:GetMouseLocation()
		else camera.ViewportSize / 2
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * Config.Input.AimDistance, params)
	local target = if result then result.Position else ray.Origin + ray.Direction * Config.Input.AimDistance
	local direction = target - (root.Position + Vector3.new(0, Config.Combat.EyeHeight, 0))
	if direction.Magnitude < 1e-3 then
		return nil
	end
	return direction.Unit
end

function InputController.selectedSlot(): number
	return selected
end

function InputController.selectSlot(slot: number)
	selected = (slot - 1) % Config.Inventory.Slots + 1
	for _, listener in slotListeners do
		listener(selected)
	end
end

function InputController.onSlotChanged(listener: (slot: number) -> ())
	table.insert(slotListeners, listener)
end

function InputController.attack()
	local aim = aimDirection()
	if aim then
		requestAttack:FireServer(selected, aim)
	end
end

function InputController.useItem()
	requestUseItem:FireServer(selected)
end

-- Sprinting is client-side movement, like walking itself.
function InputController.setSprinting(on: boolean)
	sprinting = on
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.WalkSpeed = if on then Config.Movement.SprintSpeed else Config.Movement.WalkSpeed
	end
end

-- Shows or hides the touch buttons (only ever shown on touch devices).
function InputController.setTouchButtonsVisible(visible: boolean)
	if touchGui then
		touchGui.Enabled = visible and UserInputService.TouchEnabled
	end
end

local function makeTouchButton(parent: Instance, text: string, rightOffset: number, bottomOffset: number): TextButton
	local size = Config.Hud.TouchButtonSize
	local button = Instance.new("TextButton")
	button.Name = text
	button.Text = text
	button.Font = Enum.Font.BuilderSansBold
	button.TextSize = Config.Hud.TextSize
	button.TextColor3 = Color3.fromRGB(table.unpack(Config.Colors.Text))
	button.BackgroundColor3 = Color3.fromRGB(table.unpack(Config.Colors.Panel))
	button.BackgroundTransparency = Config.Hud.PanelTransparency
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.fromOffset(size, size)
	button.Position = UDim2.new(1, -rightOffset, 1, -bottomOffset)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	button.Parent = parent
	return button
end

-- Attack, Use and Sprint buttons, stacked left of and above the default jump button.
local function buildTouchButtons()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TouchControls"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local size = Config.Hud.TouchButtonSize
	local gap = Config.Hud.Padding
	local attack = makeTouchButton(gui, "Attack", size + gap * 2, gap * 2)
	local use = makeTouchButton(gui, "Use", size * 2 + gap * 3, gap * 2)
	local sprint = makeTouchButton(gui, "Sprint", gap * 2, size + gap * 4)
	attack.Activated:Connect(InputController.attack)
	use.Activated:Connect(InputController.useItem)
	sprint.Activated:Connect(function()
		InputController.setSprinting(not sprinting) -- a toggle is easier than holding on a phone
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	touchGui = gui
end

function InputController.start()
	buildTouchButtons()

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return -- typing in chat, clicking a button, and so on
		end
		local key = input.KeyCode
		if input.UserInputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
			InputController.attack()
		elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonY then
			InputController.useItem()
		elseif key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.ButtonL3 then
			InputController.setSprinting(true)
		elseif key == Enum.KeyCode.ButtonR1 then
			InputController.selectSlot(selected + 1)
		elseif key == Enum.KeyCode.ButtonL1 then
			InputController.selectSlot(selected - 1)
		elseif SLOT_KEYS[key] then
			InputController.selectSlot(SLOT_KEYS[key])
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
			InputController.setSprinting(false)
		end
	end)

	player.CharacterAdded:Connect(function()
		sprinting = false
	end)
end

return InputController
