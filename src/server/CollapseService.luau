--!strict
-- The Collapse: gets each moment's border radius from Collapse, moves a visible wall to it,
-- and damages Entrants outside it. Clients hear about each stage through CollapseChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Collapse = require(ReplicatedStorage.Shared.Collapse)
local Config = require(ReplicatedStorage.Shared.Config)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local CombatService = require(script.Parent.CombatService)
local Entrants = require(script.Parent.Entrants)
local Remotes = require(script.Parent.Remotes)

local CollapseService = {}

local arena: ArenaBuilder.Arena? = nil
local startedAt = 0 -- server time the Active phase began
local stage = 0
local radius = 0
local segments: { Part } = {}
local sinceUpdate = 0

-- Places the wall segments as a polygon inscribed in a circle of `wallRadius`: each segment
-- spans one chord, so the ring closes without gaps or overlap at any radius.
local function placeWall(wallRadius: number)
	local count = #segments
	local height = Config.Collapse.WallHeight
	local chord = 2 * wallRadius * math.sin(math.pi / count)
	local apothem = wallRadius * math.cos(math.pi / count)
	for index, segment in segments do
		local angle = (index - 0.5) * 2 * math.pi / count
		local position = Vector3.new(apothem * math.cos(angle), height / 2, apothem * math.sin(angle))
		segment.Size = Vector3.new(chord, height, Config.Collapse.WallThickness)
		segment.CFrame = CFrame.lookAt(position, Vector3.new(0, height / 2, 0))
	end
end

local function buildWall(parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "CollapseWall"
	local color = Config.Colors.CollapseWall
	segments = {}
	for _ = 1, Config.Collapse.WallSegments do
		local segment = Instance.new("Part")
		segment.Name = "Segment"
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false -- arrows and line-of-sight checks pass through
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.SmoothPlastic
		segment.Color = Color3.fromRGB(color[1], color[2], color[3])
		segment.Transparency = Config.Collapse.WallTransparency
		segment.Parent = folder
		table.insert(segments, segment)
	end
	folder.Parent = parent
end

-- The border radius right now (0 outside the Active phase).
function CollapseService.currentRadius(): number
	return radius
end

-- The radius the border is closing to in the current stage.
function CollapseService.targetRadius(): number
	if not arena then
		return 0
	end
	return Collapse.stageRadius(arena.size.ArenaRadius, arena.size.CollapseStages, stage)
end

local function update(dt: number)
	local current = arena
	if not current then
		return
	end
	local size = current.size
	local elapsed = workspace:GetServerTimeNow() - startedAt
	radius = Collapse.radiusAt(size.ArenaRadius, size.CollapseStages, elapsed)
	placeWall(radius)

	local nowStage = Collapse.stageAt(size.CollapseStages, elapsed)
	if nowStage ~= stage then
		stage = nowStage
		if stage > size.CollapseStages then
			Remotes.collapseChanged(Config.Collapse.FinalRadius, 0) -- holding at the final radius
		else
			Remotes.collapseChanged(CollapseService.targetRadius(), startedAt + Collapse.stageEndsAt(stage))
		end
	end

	for _, entrant in Entrants.living() do
		local root = Entrants.rootPart(entrant)
		if root then
			local offset = root.Position - current.center
			if Collapse.isOutside(radius, offset.X, offset.Z) then
				CombatService.damage(entrant, Config.Collapse.DamagePerSecondOutside * dt, nil)
			end
		end
	end
end

function CollapseService.onPhaseChanged(phase: string, roundArena: ArenaBuilder.Arena?, activeStartedAt: number)
	if phase == "Active" and roundArena then
		arena = roundArena
		startedAt = activeStartedAt
		stage = 0
		sinceUpdate = 0
		buildWall(roundArena.model)
		update(0)
	elseif phase == "Results" or phase == "Waiting" then
		arena = nil
		radius = 0
		segments = {} -- the parts go with the arena model
	end
end

function CollapseService.start()
	RunService.Heartbeat:Connect(function(dt: number)
		if not arena then
			return
		end
		sinceUpdate += dt
		if sinceUpdate >= Config.Collapse.UpdateSeconds then
			local elapsed = sinceUpdate
			sinceUpdate = 0
			update(elapsed)
		end
	end)
end

return CollapseService
