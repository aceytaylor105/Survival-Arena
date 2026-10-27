--!strict
-- Builds the greybox map from Config: the lobby platform once, and each round a disc sized
-- to the lobby size with the Supply Spire in the center, spawn pads on a ring and crates.
-- Anchored parts, flat colors only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbySize = require(ReplicatedStorage.Shared.LobbySize)

export type Arena = {
	model: Model,
	sizeName: LobbySize.SizeName,
	size: LobbySize.Size,
	center: Vector3, -- top of the floor at the arena center
	pads: { CFrame }, -- where each Entrant stands, facing the Spire
	crates: { BasePart },
}

local ArenaBuilder = {}

local arenaModel: Model? = nil
local lobbyModel: Model? = nil

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: { number }, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = rgb(color)
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A flat cylinder (disc) whose top face sits at `topY`. Roblox cylinders run along X, so
-- the part is rolled 90 degrees to stand upright.
local function makeDisc(name: string, diameter: number, height: number, x: number, topY: number, z: number, color: { number }, parent: Instance): Part
	local part = makePart(
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(x, topY - height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		parent
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function ringPoint(radius: number, index: number, count: number, angleOffset: number): (number, number)
	local angle = angleOffset + (index - 1) * (2 * math.pi / count)
	return radius * math.cos(angle), radius * math.sin(angle)
end

-- A crate part. LootService gives it a tier, contents and a prompt.
function ArenaBuilder.makeCrate(position: Vector3, atSpire: boolean, parent: Instance): Part
	local crateSize = Config.Arena.CrateSize
	local part = makePart(
		"Crate",
		Vector3.new(crateSize, crateSize, crateSize),
		CFrame.lookAt(position + Vector3.new(0, crateSize / 2, 0), Vector3.new(0, crateSize / 2, 0)),
		Config.Colors.Pad,
		parent
	)
	part:SetAttribute("AtSpire", atSpire)
	return part
end

-- Ring of crate positions around the Supply Spire, `ringGaps` gaps out from its base.
function ArenaBuilder.spireRing(count: number, ringGaps: number, angleOffset: number): { Vector3 }
	local radius = Config.Arena.SpireBaseRadius + Config.Arena.SpireCrateRingGap * ringGaps
	local points = {}
	for index = 1, count do
		local x, z = ringPoint(radius, index, count, angleOffset)
		table.insert(points, Vector3.new(x, 0, z))
	end
	return points
end

local function scatterCrates(arenaRadius: number, count: number, padPoints: { Vector3 }, random: Random): { Vector3 }
	local inner = Config.Arena.SpireBaseRadius + Config.Arena.SpireCrateRingGap * 3
	local outer = arenaRadius - Config.Arena.CrateEdgeMargin
	local points = {}
	for _ = 1, count do
		local point = Vector3.zero
		for _ = 1, Config.Arena.CratePlacementTries do
			-- sqrt keeps the spread even across the area rather than bunched at the center
			local radius = math.sqrt(random:NextNumber(inner * inner, outer * outer))
			local angle = random:NextNumber(0, 2 * math.pi)
			point = Vector3.new(radius * math.cos(angle), 0, radius * math.sin(angle))
			local clear = true
			for _, pad in padPoints do
				if (pad - point).Magnitude < Config.Arena.CratePadClearance then
					clear = false
					break
				end
			end
			if clear then
				break
			end
		end
		table.insert(points, point)
	end
	return points
end

-- Builds the lobby platform once; later calls return the same model.
function ArenaBuilder.buildLobby(): Model
	if lobbyModel then
		return lobbyModel
	end
	local lobby = Config.Lobby
	local model = Instance.new("Model")
	model.Name = "Lobby"

	local thickness = Config.Arena.FloorThickness
	makePart(
		"Floor",
		Vector3.new(lobby.Size, thickness, lobby.Size),
		CFrame.new(lobby.CenterX, -thickness / 2, 0),
		Config.Colors.Lobby,
		model
	)
	local half = lobby.Size / 2
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local alongX = side.X == 0
		makePart(
			"Wall",
			if alongX then Vector3.new(lobby.Size, lobby.WallHeight, 1) else Vector3.new(1, lobby.WallHeight, lobby.Size),
			CFrame.new(lobby.CenterX + side.X * half, lobby.WallHeight / 2, side.Z * half),
			Config.Colors.LobbyWall,
			model
		)
	end

	-- Default spawn point, so a freshly loaded character appears in the lobby.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(lobby.Size * lobby.SpawnFraction, 1, lobby.Size * lobby.SpawnFraction)
	spawn.CFrame = CFrame.new(lobby.CenterX, 0.5, 0)
	spawn.Duration = 0 -- no spawn force field
	spawn.Neutral = true
	spawn.Parent = model

	model.Parent = workspace
	lobbyModel = model
	return model
end

-- A random standing spot in the lobby.
function ArenaBuilder.lobbySpawn(random: Random): CFrame
	local reach = Config.Lobby.Size / 2 * Config.Lobby.SpawnFraction
	local position = Vector3.new(
		Config.Lobby.CenterX + random:NextNumber(-reach, reach),
		Config.Arena.SpawnHeight,
		random:NextNumber(-reach, reach)
	)
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

-- Builds the arena for a round, replacing any previous one. `entrantCount` sets the crate
-- count; `seed` makes crate placement repeatable.
function ArenaBuilder.build(sizeName: LobbySize.SizeName, entrantCount: number, seed: number): Arena
	ArenaBuilder.clear()

	local size = LobbySize.get(sizeName)
	local arenaConfig = Config.Arena
	local random = Random.new(seed)
	local model = Instance.new("Model")
	model.Name = "Arena"

	makeDisc("Floor", size.ArenaRadius * 2, arenaConfig.FloorThickness, 0, 0, 0, Config.Colors.Floor, model)

	-- Supply Spire: a low round base with a tall tower on it.
	local spire = Instance.new("Model")
	spire.Name = "SupplySpire"
	makeDisc(
		"Base",
		arenaConfig.SpireBaseRadius * 2,
		arenaConfig.SpireBaseHeight,
		0,
		arenaConfig.SpireBaseHeight,
		0,
		Config.Colors.SpireBase,
		spire
	)
	makePart(
		"Tower",
		Vector3.new(arenaConfig.SpireWidth, arenaConfig.SpireHeight, arenaConfig.SpireWidth),
		CFrame.new(0, arenaConfig.SpireBaseHeight + arenaConfig.SpireHeight / 2, 0),
		Config.Colors.Spire,
		spire
	)
	spire.Parent = model

	-- Spawn pads: one per possible Entrant in this lobby size, on a ring facing the Spire.
	local padFolder = Instance.new("Folder")
	padFolder.Name = "SpawnPads"
	padFolder.Parent = model
	local ringRadius = size.ArenaRadius * Config.Round.SpawnRingFraction
	local standY = arenaConfig.PadHeight + arenaConfig.SpawnHeight
	local pads: { CFrame } = {}
	local padPoints: { Vector3 } = {}
	for index = 1, size.MaxPlayers do
		local x, z = ringPoint(ringRadius, index, size.MaxPlayers, 0)
		local pad = makeDisc("Pad", arenaConfig.PadDiameter, arenaConfig.PadHeight, x, arenaConfig.PadHeight, z, Config.Colors.Pad, padFolder)
		pad:SetAttribute("PadIndex", index)
		table.insert(pads, CFrame.lookAt(Vector3.new(x, standY, z), Vector3.new(0, standY, 0)))
		table.insert(padPoints, Vector3.new(x, 0, z))
	end

	-- Crates: a share ring the Spire, the rest scatter between the Spire and the edge.
	local crateFolder = Instance.new("Folder")
	crateFolder.Name = "Crates"
	crateFolder.Parent = model
	local total = Config.Loot.CratesPerPlayer * entrantCount
	local atSpire = math.min(total, math.ceil(total * arenaConfig.SpireCrateShare))
	local crates: { BasePart } = {}
	for _, point in ArenaBuilder.spireRing(atSpire, 1, 0) do
		table.insert(crates, ArenaBuilder.makeCrate(point, true, crateFolder))
	end
	for _, point in scatterCrates(size.ArenaRadius, total - atSpire, padPoints, random) do
		table.insert(crates, ArenaBuilder.makeCrate(point, false, crateFolder))
	end

	model.Parent = workspace
	arenaModel = model

	return {
		model = model,
		sizeName = sizeName,
		size = size,
		center = Vector3.zero,
		pads = pads,
		crates = crates,
	}
end

function ArenaBuilder.clear()
	if arenaModel then
		arenaModel:Destroy()
		arenaModel = nil
	end
end

return ArenaBuilder
