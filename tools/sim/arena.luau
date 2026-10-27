--!nocheck
-- Not type-checked: drives the fake engine in Engine.luau.
--
-- ArenaBuilder geometry for all three lobby sizes: pad counts and ring, the Spire in the
-- center, floor size, crate counts and placement, and a single arena at a time.

local Engine = require("./Engine")
local check = Engine.check

local server = Engine.loadServer()
local ArenaBuilder = Engine.require(server.ArenaBuilder)
local Config = Engine.require(Engine.game.ReplicatedStorage.Shared.Config)
local workspace = Engine.workspace

local lobby = ArenaBuilder.buildLobby()
check(lobby.Parent == workspace and lobby:FindFirstChild("LobbySpawn") ~= nil, "the lobby is built with a spawn point")
check(ArenaBuilder.buildLobby() == lobby, "building the lobby twice returns the same lobby")

local EPSILON = 1e-3

for _, case in { { "Showdown", 5 }, { "Skirmish", 8 }, { "FullArena", 24 } } do
	local name, entrants = case[1], case[2]
	local size = Config.LobbySizes[name]
	local arena = ArenaBuilder.build(name, entrants, 42)
	print(name)

	local pads = arena.model.SpawnPads:GetChildren()
	check(#pads == size.MaxPlayers and #arena.pads == size.MaxPlayers, `{#pads} spawn pads for up to {size.MaxPlayers} Entrants`)

	local tower = arena.model.SupplySpire.Tower.Position
	check(math.abs(tower.X) < EPSILON and math.abs(tower.Z) < EPSILON, "the Supply Spire is at the center")

	local floor = arena.model.Floor
	check(math.abs(floor.Size.Y - size.ArenaRadius * 2) < EPSILON, `the floor is {size.ArenaRadius * 2} studs across`)
	check(math.abs(floor.Position.Y + floor.Size.X / 2) < EPSILON, "the floor's top is at y = 0")

	local ring = size.ArenaRadius * Config.Round.SpawnRingFraction
	local onRing, facing = true, true
	for _, pad in pads do
		local p = pad.Position
		if math.abs(math.sqrt(p.X ^ 2 + p.Z ^ 2) - ring) > EPSILON then
			onRing = false
		end
	end
	for _, stand in arena.pads do
		local p = stand.Position
		local dx, dz = -p.X, -p.Z
		local length = math.sqrt(dx * dx + dz * dz)
		local look = stand.LookVector
		if math.abs(look.X - dx / length) > EPSILON or math.abs(look.Z - dz / length) > EPSILON then
			facing = false
		end
	end
	check(onRing, `every pad sits on the ring at {ring} studs`)
	check(facing, "Entrants on the pads face the Spire")

	local crates = arena.model.Crates:GetChildren()
	check(#crates == Config.Loot.CratesPerPlayer * entrants, `{#crates} crates for {entrants} Entrants`)
	local inside, atSpire = true, 0
	for _, crate in crates do
		local p = crate.Position
		if math.sqrt(p.X ^ 2 + p.Z ^ 2) > size.ArenaRadius - Config.Arena.CrateEdgeMargin + EPSILON then
			inside = false
		end
		if crate:GetAttribute("AtSpire") then
			atSpire += 1
		end
	end
	check(inside, "every crate is inside the edge margin")
	check(atSpire == math.ceil(#crates * Config.Arena.SpireCrateShare), `{atSpire} crates ring the Spire`)
end

local arenas = 0
for _, child in workspace:GetChildren() do
	if child.Name == "Arena" then
		arenas += 1
	end
end
check(arenas == 1, "building a new arena replaces the old one")
ArenaBuilder.clear()
check(workspace:FindFirstChild("Arena") == nil, "clear removes the arena")

Engine.finish("arena")
