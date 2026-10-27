--!strict
-- Checks each attack (alive, cooldown, range, line of sight), applies damage from Combat,
-- and handles knockouts: a stylized burst of particles, then the Entrant is a spectator.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = require(ReplicatedStorage.Shared.Combat)
local Config = require(ReplicatedStorage.Shared.Config)
local Entrants = require(script.Parent.Entrants)
local LootService = require(script.Parent.LootService)
local Remotes = require(script.Parent.Remotes)

type KnockoutListener = (victim: Entrants.Entrant, by: Entrants.Entrant?) -> ()

local CombatService = {}

local combatOpen = false
local knockoutListeners: { KnockoutListener } = {}

local function rgb(color: { number }): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function toPoint(vector: Vector3): Combat.Point
	return { x = vector.X, y = vector.Y, z = vector.Z }
end

local function excluding(instances: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = instances
	params.IgnoreWater = true
	return params
end

-- Effects ----------------------------------------------------------------------------------

local function effectPart(name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	return part
end

local function drawTracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length <= 0 then
		return
	end
	local width = Config.Combat.TracerWidth
	local tracer = effectPart("Tracer", Vector3.new(width, width, length), CFrame.lookAt((from + to) / 2, to))
	tracer.Material = Enum.Material.SmoothPlastic
	tracer.Color = rgb(Config.Colors.Tracer)
	tracer.Parent = workspace
	Debris:AddItem(tracer, Config.Combat.TracerSeconds)
end

local function flash(entrant: Entrants.Entrant)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = rgb(Config.Colors.HitFlash)
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = entrant.character
	Debris:AddItem(highlight, Config.Combat.HitFlashSeconds)
end

-- Stylized knockout: a burst of bright sparkles where the Entrant stood. No gore.
local function burst(position: Vector3)
	local anchor = effectPart("KnockoutBurst", Vector3.one, CFrame.new(position))
	anchor.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Color = ColorSequence.new(rgb(Config.Colors.KnockoutBurst), Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.5, 1)
	emitter.Speed = NumberRange.new(12, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new(1.2, 0)
	emitter.Drag = 4
	emitter.Parent = anchor
	anchor.Parent = workspace
	emitter:Emit(Config.Combat.KnockoutParticles)
	Debris:AddItem(anchor, Config.Combat.KnockoutEffectSeconds)
end

-- Damage and knockouts ---------------------------------------------------------------------

function CombatService.onKnockout(listener: KnockoutListener)
	table.insert(knockoutListeners, listener)
end

-- Knocks the Entrant out of the round. `by` is the Entrant who did it; nil means the arena
-- (the Collapse, hunger, a fall, or leaving the server).
function CombatService.knockOut(victim: Entrants.Entrant, by: Entrants.Entrant?)
	if not victim.alive then
		return
	end
	Entrants.markOut(victim)
	victim.health = 0
	Entrants.sendStats(victim)

	local root = Entrants.rootPart(victim)
	if root then
		burst(root.Position)
	end
	local player = victim.player
	if player and player.Character == victim.character then
		player.Character = nil
	end
	victim.character:Destroy()

	Remotes.knockedOut(victim.name, if by then by.name else nil)
	for _, listener in knockoutListeners do
		task.spawn(listener, victim, by)
	end
end

-- Applies `amount` damage. `by` is the attacking Entrant, or nil for the arena itself.
function CombatService.damage(victim: Entrants.Entrant, amount: number, by: Entrants.Entrant?)
	if not victim.alive then
		return
	end
	local health, knockedOut = Combat.applyDamage(victim.health, amount)
	victim.health = health
	if knockedOut then
		CombatService.knockOut(victim, by)
		return
	end
	Entrants.sendStats(victim)
	if by then
		flash(victim)
	end
end

-- Attacks ----------------------------------------------------------------------------------

local function shoot(attacker: Entrants.Entrant, origin: Vector3, aim: Vector3, weapon: Combat.Weapon)
	local result = workspace:Raycast(origin, aim * weapon.Range, excluding({ attacker.character }))
	drawTracer(origin, if result then result.Position else origin + aim * weapon.Range)
	if not result then
		return
	end
	local victim = Entrants.fromInstance(result.Instance)
	if victim and victim ~= attacker and victim.alive then
		CombatService.damage(victim, weapon.Damage, attacker)
	end
end

local function strike(attacker: Entrants.Entrant, origin: Vector3, aim: Vector3, weapon: Combat.Weapon)
	local candidates: { Entrants.Entrant } = {}
	local points: { Combat.Point } = {}
	for _, entrant in Entrants.living() do
		local root = Entrants.rootPart(entrant)
		if entrant ~= attacker and root then
			table.insert(candidates, entrant)
			table.insert(points, toPoint(root.Position))
		end
	end

	for _, index in Combat.meleeTargets(toPoint(origin), toPoint(aim), weapon, points) do
		local victim = candidates[index]
		local root = Entrants.rootPart(victim)
		if root then
			-- Line of sight: nothing solid between the attacker's eyes and the target.
			local blocked = workspace:Raycast(origin, root.Position - origin, excluding({ attacker.character, victim.character }))
			if not blocked then
				CombatService.damage(victim, weapon.Damage, attacker)
				return
			end
		end
	end
end

-- Attacks with the weapon in `slot` toward the unit vector `aim`. Returns true if the attack
-- happened (it may still miss); false if it was refused.
function CombatService.attack(attacker: Entrants.Entrant, slot: number, aim: Vector3): boolean
	if not combatOpen or not attacker.alive then
		return false
	end
	local item = LootService.itemAt(attacker, slot)
	local weapon = if item then Combat.weapon(item) else nil
	local root = Entrants.rootPart(attacker)
	if not item or not weapon or not root then
		return false
	end
	local now = os.clock()
	if not Combat.isReady(now, attacker.attackReadyAt) then
		return false
	end
	attacker.attackReadyAt = Combat.readyAtAfter(now, weapon)

	-- Positions come from the server's copy of the character, never from the client.
	local origin = root.Position + Vector3.new(0, Config.Combat.EyeHeight, 0)
	if Combat.isRanged(item) then
		shoot(attacker, origin, aim, weapon)
	else
		strike(attacker, origin, aim, weapon)
	end
	return true
end

function CombatService.onPhaseChanged(phase: string)
	combatOpen = phase == "Active"
end

return CombatService
