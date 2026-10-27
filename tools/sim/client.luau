--!nocheck
-- Not type-checked: drives the fake engine in Engine.luau.
--
-- The real client modules (input, HUD, spectate) against fake services on a phone-sized
-- touch screen: every server-to-client remote, keys, touch buttons, the Collapse warning,
-- a knockout into spectating, and the reset back to the lobby.

local roblox = require("@lune/roblox")
local Engine = require("./Engine")
local check = Engine.check
local CFrame, Vector2, Vector3, Enum = roblox.CFrame, roblox.Vector2, roblox.Vector3, roblox.Enum
local Fake, define = Engine.Fake, Engine.define
local game, workspace = Engine.game, Engine.workspace

-- Shared modules, and remotes as the server would create them.
Engine.loadServer()
local remotes = Fake.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = game:GetService("ReplicatedStorage")
for _, name in {
	"RequestAttack",
	"RequestUseItem",
	"PhaseChanged",
	"StatsChanged",
	"PlayersLeftChanged",
	"CollapseChanged",
	"KnockedOut",
	"InventoryChanged",
	"FeastStarted",
} do
	local remote = Fake.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
end
local function fire(name, ...)
	remotes[name].OnClientEvent:Fire(...)
end
local function lastSent()
	for index = #Engine.log, 1, -1 do
		if Engine.log[index].to == "server" then
			return Engine.log[index]
		end
	end
	return nil
end

-- The local player, their character and the camera.
local player = Fake.new("Player")
player.Name = "Tester"
player.Parent = game:GetService("Players")
game:GetService("Players").LocalPlayer = player
local playerGui = Fake.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player

local character = Fake.new("Model")
character.Name = "Tester"
local root = Fake.new("Part")
root.Name = "HumanoidRootPart"
root.CFrame = CFrame.new(0, 3, 50)
root.Parent = character
Fake.new("Humanoid").Parent = character
character.Parent = workspace
player.Character = character
character:AddTag("LivingEntrant")

local camera = Fake.new("Camera")
camera.ViewportSize = Vector2.new(844, 390) -- a phone in landscape
camera.CFrame = CFrame.lookAt(Vector3.new(0, 10, 70), Vector3.new(0, 3, 0))
workspace.CurrentCamera = camera
define("Camera", {
	ViewportPointToRay = function(self)
		return { Origin = self.CFrame.Position, Direction = self.CFrame.LookVector }
	end,
})

-- Services the client uses.
local input = game:GetService("UserInputService")
input.TouchEnabled = true
define("UserInputService", {
	GetLastInputType = function()
		return Enum.UserInputType.Touch
	end,
	GetMouseLocation = function()
		return Vector2.new(422, 195)
	end,
})
local tagRemoved = Engine.Signal.new()
define("CollectionService", {
	GetTagged = function(_self, tag)
		local tagged = {}
		for _, descendant in workspace:GetDescendants() do
			if descendant:HasTag(tag) then
				table.insert(tagged, descendant)
			end
		end
		return tagged
	end,
	GetInstanceRemovedSignal = function()
		return tagRemoved
	end,
})
local core = {}
define("StarterGui", {
	SetCoreGuiEnabled = function(_self, kind, enabled)
		core[tostring(kind)] = enabled
	end,
	SetCore = function(_self, name, value)
		core[name] = value
	end,
})

-- An arena with a wall at radius 100 around the origin, and one bot to spectate.
local arena = Fake.new("Model")
arena.Name = "Arena"
arena.Parent = workspace
local floor = Fake.new("Part")
floor.Name = "Floor"
floor.CFrame = CFrame.new(0, -2, 0)
floor.Parent = arena
local wall = Fake.new("Folder")
wall.Name = "CollapseWall"
wall.Parent = arena
local segment = Fake.new("Part")
segment.Size = Vector3.new(2 * 100 * math.sin(math.pi / 48), 80, 1)
segment.CFrame = CFrame.new(100 * math.cos(math.pi / 48), 40, 0)
segment.Parent = wall
local bot = Fake.new("Model")
bot.Name = "Bot 1"
bot.Parent = workspace
local botHumanoid = Fake.new("Humanoid")
botHumanoid.DisplayName = "Bot 1"
botHumanoid.Parent = bot
bot:AddTag("LivingEntrant")

-- Run the client.
Engine.startHeartbeat()
Engine.runScript(Engine.loadClient())
Engine.runFor(1)

check(
	core["Enum.CoreGuiType.Backpack"] == false
		and core["Enum.CoreGuiType.Health"] == false
		and core.ResetButtonCallback == false,
	"the backpack, default health bar and reset button are off"
)
local hud = playerGui:FindFirstChild("Hud")
local touch = playerGui:FindFirstChild("TouchControls")
local spectate = playerGui:FindFirstChild("Spectate")
check(hud ~= nil and touch ~= nil and spectate ~= nil, "the HUD, touch controls and spectate bar are built")
local function text(path)
	local node = hud
	for part in string.gmatch(path, "[^.]+") do
		node = node[part]
	end
	return node.Text
end

-- Phases, stats and inventory
fire("PhaseChanged", "Waiting", Engine.now() + 42)
Engine.runFor(0.3)
check(text("Top.Phase") == "Round starts in 0:42", `queue timer reads "{text("Top.Phase")}"`)
fire("PhaseChanged", "Active", Engine.now() + 450)
fire("PlayersLeftChanged", 8)
fire("CollapseChanged", 246, Engine.now() + 90)
fire("StatsChanged", 75, 40)
fire("InventoryChanged", { "Spear", "FeastBasket", "", "", "", "" })
Engine.runFor(0.3)
check(string.find(text("Top.Phase"), "7:30", 1, true) ~= nil, `round timer reads "{text("Top.Phase")}"`)
check(text("Top.Info") == "8 left  ·  border closing to 246 in 1:30", `info line reads "{text("Top.Info")}"`)
check(
	text("Vitals.Health.Value") == "Health 75" and text("Vitals.Hunger.Value") == "Hunger 40",
	"health and hunger show the server's numbers"
)
check(
	hud.Slots.Slot1.Text == "Spear" and hud.Slots.Slot2.Text == "Feast Basket" and hud.Slots.Slot3.Text == "",
	"inventory slots show item names"
)
check(touch.Enabled == true, "touch buttons show during Active on a touch screen")
check(hud.Top.Warning.Visible == false, "no Collapse warning well inside the border")

-- Collapse warnings
root.CFrame = CFrame.new(0, 3, 95)
Engine.runFor(0.3)
check(hud.Top.Warning.Visible and string.find(hud.Top.Warning.Text, "closing in", 1, true) ~= nil, "a warning near the border")
root.CFrame = CFrame.new(0, 3, 120)
Engine.runFor(0.3)
check(hud.Top.Warning.Visible and string.find(hud.Top.Warning.Text, "Outside", 1, true) ~= nil, "a danger warning outside it")
root.CFrame = CFrame.new(0, 3, 50)

-- Touch buttons and keys
hud.Slots.Slot1.Activated:Fire()
touch.Attack.Activated:Fire()
local sent = lastSent()
check(
	sent ~= nil and sent.remote == "RequestAttack" and sent.args[1] == 1 and math.abs(sent.args[2].Magnitude - 1) < 1e-6,
	"the touch Attack button sends slot 1 and a unit aim"
)
local function key(code, began)
	local event = { KeyCode = Enum.KeyCode[code], UserInputType = Enum.UserInputType.Keyboard }
	if began == false then
		input.InputEnded:Fire(event, false)
	else
		input.InputBegan:Fire(event, false)
	end
end
key("Two")
check(
	hud.Slots.Slot2.UIStroke.Thickness == 3 and hud.Slots.Slot1.UIStroke.Thickness == 1,
	"key 2 selects slot 2 and the HUD highlights it"
)
key("F")
sent = lastSent()
check(sent.remote == "RequestUseItem" and sent.args[1] == 2, "F eats from the selected slot")
input.InputBegan:Fire({ KeyCode = Enum.KeyCode.F, UserInputType = Enum.UserInputType.Keyboard }, true)
check(lastSent() == sent, "keys typed into chat are ignored")
key("LeftShift")
check(character.Humanoid.WalkSpeed == 24, "holding Shift sprints")
key("LeftShift", false)
check(character.Humanoid.WalkSpeed == 16, "letting go walks")
touch.Sprint.Activated:Fire()
check(character.Humanoid.WalkSpeed == 24, "the touch Sprint button turns sprint on")
touch.Sprint.Activated:Fire()
check(character.Humanoid.WalkSpeed == 16, "and off again")

-- The Feast and knockouts
fire("FeastStarted")
Engine.runFor(0.1)
check(hud.Banner.Visible and string.find(hud.Banner.Text, "Feast", 1, true) ~= nil, "the Feast banner shows")
fire("KnockedOut", "Bot 2", "Tester")
fire("KnockedOut", "Bot 3", nil)
Engine.runFor(0.1)
local lines = {}
for _, child in hud.Feed:GetChildren() do
	if child:IsA("TextLabel") then
		table.insert(lines, child.Text)
	end
end
check(
	table.find(lines, "Tester knocked out Bot 2") ~= nil and table.find(lines, "Bot 3 was knocked out by the arena") ~= nil,
	"the knockout feed names who did it"
)

-- Our own knockout
character:RemoveTag("LivingEntrant")
player.Character = nil
character:Destroy()
fire("KnockedOut", "Tester", "Bot 1")
Engine.runFor(0.3)
check(spectate.Enabled and spectate.Bar.Target.Text == "Spectating Bot 1", "a knockout starts spectating")
check(camera.CameraSubject == botHumanoid, "the camera follows the spectated Entrant")
check(
	hud.Vitals.Visible == false and hud.Slots.Visible == false and touch.Enabled == false,
	"vitals, slots and touch buttons hide while spectating"
)
fire("PhaseChanged", "Results", Engine.now() + 15, "Bot 1")
Engine.runFor(0.3)
check(text("Top.Phase") == "Bot 1 wins!", "Results names the winner")
fire("PhaseChanged", "Waiting", 0)
Engine.runFor(0.3)
check(spectate.Enabled == false, "spectating ends when the round resets")
check(text("Top.Phase") == "Waiting for Entrants", "the lobby shows the queue again")

Engine.finish("client")
