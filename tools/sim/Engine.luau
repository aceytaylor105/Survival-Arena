--!nocheck
-- Not type-checked: this harness fakes the engine with dynamic tables and metatables.
--
-- A headless stand-in for the Roblox engine, so the real server and client modules can run
-- whole rounds in Lune in seconds. It fakes Instances (a property bag with children,
-- events, tags and attributes), runs threads on a virtual clock, walks humanoids in
-- straight lines and raycasts against characters only. It does not simulate physics,
-- collisions, replication or rendering, so it finds logic and runtime errors, not feel.
-- Vector3, CFrame and the other datatypes are Lune's real implementations.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Engine = {}

Engine.root = string.gsub(process.cwd, "/$", "")
Engine.errors = {} -- runtime errors from any thread
Engine.warnings = {} -- everything passed to warn()
Engine.log = {} -- every remote fired at clients: { time, remote, to, args }
Engine.logHook = nil -- optional function(entry) called for each log entry
Engine.bursts = 0 -- ParticleEmitter:Emit calls
Engine.blocked = setmetatable({}, { __mode = "k" }) -- [Humanoid] = true: MoveTo goes nowhere
Engine.heartbeatSeconds = 1 / 30

-- Checks -------------------------------------------------------------------------------------

local passed, failed = 0, 0

function Engine.check(ok: boolean, message: string)
	if ok then
		passed += 1
		print("  ok   " .. message)
	else
		failed += 1
		print("  FAIL " .. message)
	end
end

-- Prints errors, warnings and the tally, then exits non-zero if anything failed.
function Engine.finish(name: string)
	for _, err in Engine.errors do
		print(err)
	end
	for _, warning in Engine.warnings do
		print("warn: " .. warning)
	end
	Engine.check(#Engine.errors == 0, "no runtime errors")
	Engine.check(#Engine.warnings == 0, "no warnings")
	print(string.format("%s: %d passed, %d failed", name, passed, failed))
	process.exit(if failed == 0 then 0 else 1)
end

-- Scheduler: threads resume in virtual-time order ---------------------------------------------

local now = 0
local queue = {}
local sequence = 0

function Engine.now(): number
	return now
end

local function resume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(Engine.errors, string.format("[t=%.2f] %s", now, debug.traceback(thread, tostring(err))))
	end
end

local function schedule(at: number, thread, ...)
	sequence += 1
	table.insert(queue, { at = at, sequence = sequence, thread = thread, args = table.pack(...) })
end

local task = {}

function task.spawn(f, ...)
	local thread = if type(f) == "thread" then f else coroutine.create(f)
	resume(thread, ...)
	return thread
end

function task.defer(f, ...)
	local thread = if type(f) == "thread" then f else coroutine.create(f)
	schedule(now, thread, ...)
	return thread
end

function task.delay(seconds: number?, f, ...)
	local thread = if type(f) == "thread" then f else coroutine.create(f)
	schedule(now + (seconds or 0), thread, ...)
	return thread
end

function task.wait(seconds: number?): number
	local duration = math.max(seconds or 0, 1 / 60)
	schedule(now + duration, coroutine.running(), duration)
	return coroutine.yield()
end

Engine.task = task

-- Resumes queued threads in time order until virtual time `limit`, or until `stop()` is true.
-- Returns true when `stop` ended the run.
function Engine.run(limit: number, stop: (() -> boolean)?): boolean
	while #queue > 0 do
		local best = 1
		for index = 2, #queue do
			local a, b = queue[index], queue[best]
			if a.at < b.at or (a.at == b.at and a.sequence < b.sequence) then
				best = index
			end
		end
		local item = queue[best]
		if item.at > limit then
			break
		end
		table.remove(queue, best)
		now = item.at
		resume(item.thread, table.unpack(item.args, 1, item.args.n))
		if stop and stop() then
			return true
		end
	end
	return false
end

-- Runs for `seconds` more virtual time, or until `stop()` is true.
function Engine.runFor(seconds: number, stop: (() -> boolean)?): boolean
	return Engine.run(now + seconds, stop)
end

-- Signals --------------------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ connections = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { fn = fn, Connected = true }
	function connection:Disconnect()
		connection.Connected = false
	end
	table.insert(self.connections, connection)
	return connection
end

function Signal:Fire(...)
	for _, connection in table.clone(self.connections) do
		if connection.Connected then
			task.spawn(connection.fn, ...)
		end
	end
end

Engine.Signal = Signal

-- Instances ------------------------------------------------------------------------------------

local SUPERCLASS = {
	Part = "BasePart",
	SpawnLocation = "Part",
	MeshPart = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Workspace = "Model",
	PVInstance = "Instance",
}

local EVENTS = {
	Activated = true,
	CharacterAdded = true,
	Died = true,
	Heartbeat = true,
	InputBegan = true,
	InputEnded = true,
	OnClientEvent = true,
	OnServerEvent = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Running = true,
	Triggered = true,
}

local DEFAULTS = {
	BasePart = function(props)
		props.CFrame = CFrame.new()
		props.Size = Vector3.one
		props.Anchored = false
		props.CanCollide = true
		props.Transparency = 0
	end,
	Humanoid = function(props)
		props.WalkSpeed = 16
		props.Health = 100
		props.MaxHealth = 100
		props.DisplayName = ""
		props.Jump = false
	end,
	ProximityPrompt = function(props)
		props.Enabled = true
	end,
}

local isFake = setmetatable({}, { __mode = "k" })
local methods = {} -- [className] = { [name] = function }
local Fake = {}

local function classChain(className: string): { string }
	local chain = {}
	local class = className
	while class do
		table.insert(chain, class)
		class = SUPERCLASS[class] or (if class ~= "Instance" then "Instance" else nil)
	end
	return chain
end

local function isA(self, className: string): boolean
	return table.find(classChain(rawget(self, "_props").ClassName), className) ~= nil
end

function Fake.new(className: string)
	local self = setmetatable({
		_props = { ClassName = className, Name = className },
		_children = {},
		_attributes = {},
		_tags = {},
		_events = {},
	}, Fake)
	isFake[self] = true
	for _, class in classChain(className) do
		if DEFAULTS[class] then
			DEFAULTS[class](self._props)
		end
	end
	return self
end

Fake.__index = function(self, key)
	local props = rawget(self, "_props")
	for _, class in classChain(props.ClassName) do
		local classMethods = methods[class]
		if classMethods and classMethods[key] then
			return classMethods[key]
		end
	end
	if EVENTS[key] then
		local events = rawget(self, "_events")
		events[key] = events[key] or Signal.new()
		return events[key]
	end
	if key == "Position" and isA(self, "BasePart") then
		return props.CFrame.Position
	end
	if props[key] ~= nil then
		return props[key]
	end
	for _, child in rawget(self, "_children") do
		if child._props.Name == key then
			return child
		end
	end
	return nil
end

Fake.__newindex = function(self, key, value)
	local props = rawget(self, "_props")
	if key == "Parent" then
		local old = props.Parent
		if old then
			local siblings = rawget(old, "_children")
			local index = table.find(siblings, self)
			if index then
				table.remove(siblings, index)
			end
		end
		props.Parent = value
		if value then
			table.insert(rawget(value, "_children"), self)
		end
	elseif key == "Position" and isA(self, "BasePart") then
		props.CFrame = props.CFrame - props.CFrame.Position + value
	else
		props[key] = value
	end
end

Fake.__tostring = function(self)
	return rawget(self, "_props").Name
end

function Engine.define(className: string, definitions)
	methods[className] = methods[className] or {}
	for name, fn in definitions do
		methods[className][name] = fn
	end
end
local define = Engine.define

define("Instance", {
	IsA = isA,
	FindFirstChild = function(self, name)
		for _, child in self._children do
			if child._props.Name == name then
				return child
			end
		end
		return nil
	end,
	FindFirstChildOfClass = function(self, className)
		for _, child in self._children do
			if child._props.ClassName == className then
				return child
			end
		end
		return nil
	end,
	FindFirstChildWhichIsA = function(self, className)
		for _, child in self._children do
			if child:IsA(className) then
				return child
			end
		end
		return nil
	end,
	WaitForChild = function(self, name)
		for _ = 1, 300 do
			local child = self:FindFirstChild(name)
			if child then
				return child
			end
			task.wait(1 / 30)
		end
		error("Infinite yield on WaitForChild(" .. name .. ")")
	end,
	GetChildren = function(self)
		return table.clone(self._children)
	end,
	GetDescendants = function(self)
		local found = {}
		local function walk(node)
			for _, child in node._children do
				table.insert(found, child)
				walk(child)
			end
		end
		walk(self)
		return found
	end,
	IsDescendantOf = function(self, other)
		local node = self._props.Parent
		while node do
			if node == other then
				return true
			end
			node = node._props.Parent
		end
		return false
	end,
	GetFullName = function(self)
		local names = {}
		local node = self
		while node and node._props.ClassName ~= "DataModel" do
			table.insert(names, 1, node._props.Name)
			node = node._props.Parent
		end
		return table.concat(names, ".")
	end,
	Clone = function(self)
		local copy = Fake.new(self._props.ClassName)
		for key, value in self._props do
			if key ~= "Parent" then
				copy._props[key] = value
			end
		end
		for _, child in self._children do
			child:Clone().Parent = copy
		end
		return copy
	end,
	Destroy = function(self)
		self.Parent = nil
		rawset(self, "_destroyed", true)
		for _, child in table.clone(self._children) do
			child:Destroy()
		end
	end,
	ClearAllChildren = function(self)
		for _, child in table.clone(self._children) do
			child:Destroy()
		end
	end,
	SetAttribute = function(self, key, value)
		self._attributes[key] = value
	end,
	GetAttribute = function(self, key)
		return self._attributes[key]
	end,
	AddTag = function(self, tag)
		self._tags[tag] = true
	end,
	RemoveTag = function(self, tag)
		self._tags[tag] = nil
	end,
	HasTag = function(self, tag)
		return self._tags[tag] == true
	end,
})

local function baseParts(model)
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

define("Model", {
	GetPivot = function(self)
		local primary = self:FindFirstChild("HumanoidRootPart") or baseParts(self)[1]
		return if primary then primary.CFrame else CFrame.new()
	end,
	PivotTo = function(self, cframe)
		local offset = cframe * self:GetPivot():Inverse()
		for _, part in baseParts(self) do
			part.CFrame = offset * part.CFrame
		end
	end,
})

define("BasePart", {
	SetNetworkOwner = function(self)
		if self.Anchored then
			error("Network Ownership API cannot be called on Anchored parts or parts welded to Anchored parts.")
		end
	end,
})

define("ParticleEmitter", {
	Emit = function()
		Engine.bursts += 1
	end,
})

-- Animation: tracks only record what was played.
define("Animator", {
	LoadAnimation = function(self, animation)
		assert(animation and animation:IsA("Animation"), "LoadAnimation needs an Animation")
		assert(self:IsDescendantOf(Engine.game), "LoadAnimation needs the Animator in the DataModel")
		local track = { Animation = animation, IsPlaying = false, Speed = 1 }
		function track:Play()
			track.IsPlaying = true
		end
		function track:Stop()
			track.IsPlaying = false
		end
		function track:AdjustSpeed(speed)
			track.Speed = speed
		end
		self._tracks = self._tracks or {}
		table.insert(self._tracks, track)
		return track
	end,
})

-- Movement: MoveTo walks straight toward the target on the horizontal plane at WalkSpeed,
-- firing Humanoid.Running when a humanoid starts or stops.
local moveTargets = setmetatable({}, { __mode = "k" })
local running = setmetatable({}, { __mode = "k" })

define("Humanoid", {
	MoveTo = function(self, position)
		moveTargets[self] = position
	end,
})

local function setRunning(humanoid, speed)
	if (running[humanoid] or 0) ~= speed then
		running[humanoid] = speed
		humanoid.Running:Fire(speed)
	end
end

local function stepMovement(dt: number)
	for humanoid, target in moveTargets do
		local model = humanoid._props.Parent
		local root = model and model:FindFirstChild("HumanoidRootPart")
		if not root or rawget(model, "_destroyed") or root.Anchored or Engine.blocked[humanoid] then
			continue
		end
		local position = root.Position
		local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
		local step = humanoid.WalkSpeed * dt
		if flat.Magnitude <= step then
			model:PivotTo(CFrame.new(Vector3.new(target.X, position.Y, target.Z)) * (root.CFrame - position))
			moveTargets[humanoid] = nil
			setRunning(humanoid, 0)
		else
			local nextPosition = position + flat.Unit * step
			model:PivotTo(CFrame.lookAt(nextPosition, nextPosition + flat.Unit))
			setRunning(humanoid, humanoid.WalkSpeed)
		end
	end
end

-- The world -------------------------------------------------------------------------------------

local game = Fake.new("DataModel")
game.Name = "Game"
local services = {}

define("DataModel", {
	GetService = function(self, name)
		if not services[name] then
			local service = Fake.new(name)
			service.Parent = self
			services[name] = service
		end
		return services[name]
	end,
})

local workspace = game:GetService("Workspace")
Engine.game, Engine.workspace = game, workspace

-- A minimal R15-shaped rig. Player rigs also get an Animate script holding the default
-- idle/walk/run Animations, as real characters do.
local function makeRig(name: string, withAnimate: boolean)
	local model = Fake.new("Model")
	model.Name = name
	local root = Fake.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Parent = model
	local head = Fake.new("Part")
	head.Name = "Head"
	head.CFrame = CFrame.new(0, 1.5, 0)
	head.Parent = model
	local humanoid = Fake.new("Humanoid")
	humanoid.Parent = model
	if withAnimate then
		local animate = Fake.new("LocalScript")
		animate.Name = "Animate"
		for _, pair in { { "idle", "Animation1" }, { "walk", "WalkAnim" }, { "run", "RunAnim" } } do
			local holder = Fake.new("StringValue")
			holder.Name = pair[1]
			holder.Parent = animate
			local animation = Fake.new("Animation")
			animation.Name = pair[2]
			animation.AnimationId = "rbxassetid://" .. pair[1]
			animation.Parent = holder
		end
		animate.Parent = model
	end
	return model
end

define("Players", {
	GetPlayers = function(self)
		local players = {}
		for _, child in self._children do
			if child:IsA("Player") then
				table.insert(players, child)
			end
		end
		return players
	end,
	CreateHumanoidModelFromDescriptionAsync = function(_self, description)
		assert(description and description:IsA("HumanoidDescription"), "needs a HumanoidDescription")
		task.wait(0.05)
		return makeRig("Model", false)
	end,
})

define("Player", {
	LoadCharacterAsync = function(self)
		local old = self.Character
		if old then
			old:Destroy()
		end
		local rig = makeRig(self.Name, true)
		local lobby = workspace:FindFirstChild("Lobby")
		local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
		rig:PivotTo(if spawn then spawn.CFrame + Vector3.new(0, 3, 0) else CFrame.new(0, 3, 0))
		rig.Parent = workspace
		self.Character = rig
		self.CharacterAdded:Fire(rig)
		task.wait(0.05)
	end,
})

define("RunService", {
	IsStudio = function()
		return true
	end,
})

define("Debris", {
	AddItem = function(_self, item, seconds)
		task.delay(seconds, function()
			item:Destroy()
		end)
	end,
})

define("Workspace", {
	GetServerTimeNow = function()
		return now
	end,
	-- Characters only: each root part is a sphere of radius 2. No static geometry.
	Raycast = function(self, origin, direction, params)
		local length = direction.Magnitude
		local unit = direction.Unit
		local excluded = if params then params.FilterDescendantsInstances or {} else {}
		local best, bestDistance = nil, math.huge
		for _, descendant in self:GetDescendants() do
			if descendant._props.Name == "HumanoidRootPart" and not rawget(descendant, "_destroyed") then
				local skip = false
				for _, instance in excluded do
					if descendant == instance or descendant:IsDescendantOf(instance) then
						skip = true
					end
				end
				if not skip then
					local along = (descendant.Position - origin):Dot(unit)
					local miss = (origin + unit * along - descendant.Position).Magnitude
					if along >= 0 and along <= length and miss <= 2 and along < bestDistance then
						best, bestDistance = descendant, along
					end
				end
			end
		end
		if best then
			return { Instance = best, Position = origin + unit * bestDistance, Distance = bestDistance }
		end
		return nil
	end,
})

local function record(remote, to, ...)
	local entry = { time = now, remote = remote.Name, to = to, args = table.pack(...) }
	table.insert(Engine.log, entry)
	if Engine.logHook then
		Engine.logHook(entry)
	end
end

define("RemoteEvent", {
	FireAllClients = function(self, ...)
		record(self, "all", ...)
	end,
	FireClient = function(self, player, ...)
		record(self, player.Name, ...)
	end,
	FireServer = function(self, ...)
		record(self, "server", ...)
	end,
})

-- Fires RunService.Heartbeat at 30 Hz, after moving humanoids.
function Engine.startHeartbeat()
	local runService = game:GetService("RunService")
	task.spawn(function()
		while true do
			local dt = task.wait(Engine.heartbeatSeconds)
			stepMovement(dt)
			runService.Heartbeat:Fire(dt)
		end
	end)
end

-- Globals ----------------------------------------------------------------------------------------

local RandomClass = {}
RandomClass.__index = RandomClass
local seedCounter = 0

function RandomClass.new(seed: number?)
	seedCounter += 1
	return setmetatable({ state = (seed or seedCounter * 7919) % 2147483647 + 1 }, RandomClass)
end

function RandomClass:_next(): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end

function RandomClass:NextNumber(min: number?, max: number?): number
	local low, high = min or 0, max or 1
	return low + (high - low) * self:_next()
end

function RandomClass:NextInteger(min: number, max: number): number
	return math.floor(min + (max - min + 1) * self:_next())
end

function RandomClass:NextUnitVector()
	local vector = Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1))
	return if vector.Magnitude > 0 then vector.Unit else Vector3.xAxis
end

local RaycastParams = {
	new = function()
		return { FilterDescendantsInstances = {} }
	end,
}

local fakeOs = setmetatable({
	clock = function()
		return now
	end,
}, { __index = os })

local function fakeTypeof(value)
	if type(value) == "table" and isFake[value] then
		return "Instance"
	end
	return typeof(value)
end

local InstanceLibrary = {
	new = function(className)
		return Fake.new(className)
	end,
}

-- Loading the project ----------------------------------------------------------------------------

local function moduleScript(className: string, name: string, path: string)
	local script = Fake.new(className)
	script.Name = name
	script.Source = fs.readFile(path)
	return script
end

local function loadFolder(directory: string, parent, initName: string?)
	for _, file in fs.readDir(directory) do
		local name = string.match(file, "^(.-)%.luau$")
		if name and name ~= initName then
			moduleScript("ModuleScript", name, directory .. "/" .. file).Parent = parent
		end
	end
end

-- Builds ReplicatedStorage.Shared and ServerScriptService.Server from src/ and returns the
-- server Script (not yet running).
function Engine.loadServer()
	local root = Engine.root
	local shared = Fake.new("Folder")
	shared.Name = "Shared"
	shared.Parent = game:GetService("ReplicatedStorage")
	loadFolder(root .. "/src/shared", shared, nil)
	local server = moduleScript("Script", "Server", root .. "/src/server/init.server.luau")
	server.Parent = game:GetService("ServerScriptService")
	loadFolder(root .. "/src/server", server, "init.server")
	return server
end

-- Builds StarterPlayerScripts.Client from src/client and returns the LocalScript.
function Engine.loadClient()
	local root = Engine.root
	local scripts = Fake.new("StarterPlayerScripts")
	scripts.Name = "StarterPlayerScripts"
	scripts.Parent = game:GetService("StarterPlayer")
	local client = moduleScript("LocalScript", "Client", root .. "/src/client/init.client.luau")
	client.Parent = scripts
	loadFolder(root .. "/src/client", client, "init.client")
	return client
end

local loaded = {}

local function environment(script)
	local env = {
		game = game,
		workspace = workspace,
		script = script,
		Instance = InstanceLibrary,
		Vector3 = Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		ColorSequence = roblox.ColorSequence,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = roblox.Enum,
		Random = RandomClass,
		RaycastParams = RaycastParams,
		task = task,
		os = fakeOs,
		typeof = fakeTypeof,
		print = function() end,
		warn = function(...)
			local parts = {}
			for index = 1, select("#", ...) do
				parts[index] = tostring((select(index, ...)))
			end
			table.insert(Engine.warnings, string.format("[t=%.2f] %s", now, table.concat(parts, " ")))
		end,
	}
	env.require = function(target)
		return Engine.require(target, script)
	end
	return setmetatable(env, { __index = _G })
end

-- Requires a fake ModuleScript, or a string path relative to `from` (./, ../, @self/).
function Engine.require(target, from)
	if type(target) == "string" then
		local node, rest
		if string.sub(target, 1, 2) == "./" then
			node, rest = from._props.Parent, string.sub(target, 3)
		elseif string.sub(target, 1, 3) == "../" then
			node, rest = from._props.Parent._props.Parent, string.sub(target, 4)
		elseif string.sub(target, 1, 6) == "@self/" then
			node, rest = from, string.sub(target, 7)
		else
			error("unsupported require path " .. target)
		end
		for part in string.gmatch(rest, "[^/]+") do
			node = if part == ".." then node._props.Parent else node:FindFirstChild(part)
			assert(node, "require could not resolve " .. target)
		end
		target = node
	end
	assert(isFake[target] and target._props.ClassName == "ModuleScript", "require needs a ModuleScript")
	if loaded[target] == nil then
		local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = environment(target) })
		loaded[target] = chunk()
	end
	return loaded[target]
end

-- Starts a Script or LocalScript on its own thread.
function Engine.runScript(script)
	local chunk = luau.load(script.Source, { debugName = script:GetFullName(), environment = environment(script) })
	task.spawn(chunk)
end

function Engine.addPlayer(name: string)
	local players = game:GetService("Players")
	local player = Fake.new("Player")
	player.Name = name
	player.Parent = players
	players.PlayerAdded:Fire(player)
	return player
end

Engine.Fake = Fake
return Engine
