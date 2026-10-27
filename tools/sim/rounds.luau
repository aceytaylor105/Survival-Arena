--!nocheck
-- Not type-checked: drives the fake engine in Engine.luau.
--
-- One idle human tester plus bots (FillTo) for two full loops of the real server. Along the
-- way it drives the remotes like a client would (attack spam, bad payloads, eating), holds
-- bots outside the border and with no hunger, blocks a bot to see it get unstuck, and checks
-- that bots animate. Ends with per-round results.

local roblox = require("@lune/roblox")
local Engine = require("./Engine")
local check = Engine.check
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local server = Engine.loadServer()
Engine.startHeartbeat()
Engine.runScript(server)
local tester = Engine.addPlayer("Tester")

-- Round tracking from the remote log -------------------------------------------------------------

local rounds = {}
local current = nil
local resultsSeen = 0
local twoLoopsDone = false

Engine.logHook = function(entry)
	if entry.to ~= "all" then
		return
	end
	local args = entry.args
	if entry.remote == "PhaseChanged" then
		local phase = args[1]
		if phase == "Countdown" then
			current = { knockouts = {}, feasts = 0, collapse = {}, playersLeft = {} }
			table.insert(rounds, current)
		elseif phase == "Active" and current then
			current.activeAt = entry.time
		elseif phase == "Results" and current then
			current.resultsAt = entry.time
			current.winner = args[3]
			resultsSeen += 1
		elseif phase == "Waiting" and resultsSeen >= 2 and args[2] == 0 then
			twoLoopsDone = true
		end
	elseif current then
		if entry.remote == "KnockedOut" then
			table.insert(current.knockouts, { victim = args[1], by = args[2] })
		elseif entry.remote == "FeastStarted" then
			current.feasts += 1
		elseif entry.remote == "CollapseChanged" then
			table.insert(current.collapse, args[1])
		elseif entry.remote == "PlayersLeftChanged" then
			table.insert(current.playersLeft, args[1])
		end
	end
end

-- 1. The first round starts ----------------------------------------------------------------------

print("Round 1")
check(
	Engine.runFor(600, function()
		return current ~= nil and current.activeAt ~= nil
	end),
	"the first round reaches the Active phase"
)

local Entrants = Engine.require(server.Entrants)
local LootService = Engine.require(server.LootService)
local CollapseService = Engine.require(server.CollapseService)
local Config = Engine.require(Engine.game.ReplicatedStorage.Shared.Config)
local remotes = Engine.game.ReplicatedStorage.Remotes

check(#Entrants.all() == Config.Bots.FillTo, `bots fill the round to {Config.Bots.FillTo} Entrants`)
local me = Entrants.fromPlayer(tester)
check(me ~= nil and me.alive, "the tester is a living Entrant")

local bots = {}
for _, entrant in Entrants.living() do
	if not entrant.player then
		table.insert(bots, entrant)
	end
end

-- 2. Bots animate ---------------------------------------------------------------------------------

local function playing(entrant)
	local animator = entrant.character.Humanoid:FindFirstChildOfClass("Animator")
	for _, track in (animator and animator._tracks) or {} do
		if track.IsPlaying then
			return track.Animation.Name
		end
	end
	return nil
end
local animator = bots[1].character.Humanoid:FindFirstChildOfClass("Animator")
check(animator ~= nil and #(animator._tracks or {}) == 3, "each bot loads idle, walk and run tracks")
Engine.runFor(2)
local moving = 0
for _, bot in bots do
	if bot.alive and playing(bot) == "RunAnim" then
		moving += 1
	end
end
check(moving > 0, `bots on the move play the run animation ({moving} of {#bots})`)

-- 3. Attacks through the remote: cooldown and validation -----------------------------------------

local myRoot = Entrants.rootPart(me)
local target = bots[1]
local targetRoot = Entrants.rootPart(target)
targetRoot.Anchored = true -- hold the bot still (its AI skips anchored bots)
target.character:PivotTo(myRoot.CFrame * CFrame.new(0, 0, -4))
LootService.inventory(me)[1] = "Spear"
local origin = myRoot.Position + Vector3.new(0, Config.Combat.EyeHeight, 0)
local aim = (targetRoot.Position - origin).Unit
local attack = remotes.RequestAttack.OnServerEvent
local spear = Config.Weapons.Spear.Damage

local before = target.health
for _ = 1, 20 do
	attack:Fire(tester, 1, aim)
end
check(target.health == before - spear, `20 attacks in one frame land once ({before} -> {target.health})`)
Engine.runFor(Config.Weapons.Spear.Cooldown * 0.5)
attack:Fire(tester, 1, aim)
check(target.health == before - spear, "an attack before the cooldown ends is ignored")
Engine.runFor(1.1)
local afterOne = target.health
attack:Fire(tester, 1, Vector3.new(0 / 0, 0, 0))
attack:Fire(tester, 1, aim * 2)
attack:Fire(tester, 99, aim)
attack:Fire(tester, "1", aim)
attack:Fire(tester, 1.5, aim)
attack:Fire(tester, 2, aim) -- empty slot
check(target.health == afterOne, "NaN, non-unit, out-of-range, wrong-type and empty-slot attacks are ignored")
attack:Fire(tester, 1, aim)
check(target.health == afterOne - spear, "a valid attack after the cooldown lands")
if target.alive then
	targetRoot.Anchored = false
end

-- 4. Eating through the remote --------------------------------------------------------------------

LootService.inventory(me)[2] = "Bread"
me.hunger = 50
remotes.RequestUseItem.OnServerEvent:Fire(tester, 2)
check(
	me.hunger == 50 + Config.Survival.FoodRestores.Bread and LootService.itemAt(me, 2) == nil,
	"eating Bread restores hunger and uses up the item"
)

-- 5. The wall, Collapse damage and starvation -------------------------------------------------------

Engine.runFor(30)
local wall = Engine.workspace.Arena:FindFirstChild("CollapseWall")
check(wall ~= nil and #wall:GetChildren() == Config.Collapse.WallSegments, "the Collapse wall has every segment")
local radius = CollapseService.currentRadius()
local segment = wall:GetChildren()[1]
local corner = math.sqrt(segment.Position.X ^ 2 + segment.Position.Z ^ 2 + (segment.Size.X / 2) ^ 2)
check(math.abs(corner - radius) < 0.05, `the wall's corners sit on the border radius ({math.floor(radius)} studs)`)
check(radius < Engine.workspace.Arena.Floor.Size.Y / 2, "the border has started closing")

local outside, starving = nil, nil
for _, bot in bots do
	if bot.alive and bot ~= target then
		if not outside then
			outside = bot
		elseif not starving then
			starving = bot
		end
	end
end
Entrants.rootPart(outside).Anchored = true
Entrants.rootPart(starving).Anchored = true
outside.character:PivotTo(CFrame.new(radius + 15, 4, 0))
starving.character:PivotTo(CFrame.new(0, 4, radius * 0.5))
local outsideBefore, starvingBefore = outside.health, starving.health
starving.hunger = 0
Engine.runFor(2)
local collapseDamage = outsideBefore - outside.health
local starvationDamage = starvingBefore - starving.health
check(
	collapseDamage >= Config.Collapse.DamagePerSecondOutside * 2 * 0.85,
	string.format("an Entrant outside the border takes Collapse damage (%.1f in 2 s)", collapseDamage)
)
check(
	starvationDamage >= Config.Survival.StarvingDamagePerSecond * 2 * 0.7,
	string.format("an Entrant with no hunger takes starvation damage (%.1f in 2 s)", starvationDamage)
)
-- Let them go (either may have been knocked out meanwhile).
for _, held in { outside, starving } do
	local root = Entrants.rootPart(held)
	if held.alive and root then
		held.character:PivotTo(CFrame.new(0, 4, radius * 0.3))
		root.Anchored = false
	end
end

-- 6. A blocked bot jumps and sidesteps ------------------------------------------------------------

local stuck = nil
for _, bot in bots do
	if bot.alive then
		stuck = bot
	end
end
if stuck then
	local humanoid = stuck.character.Humanoid
	humanoid.Jump = false
	Engine.blocked[humanoid] = true
	Engine.runFor(Config.Bots.ThinkSeconds * (Config.Bots.StuckThinks + 2), function()
		return humanoid.Jump == true
	end)
	check(humanoid.Jump == true, `a bot that can't move jumps to get unstuck ({stuck.name})`)
	Engine.blocked[humanoid] = nil
end

-- 7. Two full loops --------------------------------------------------------------------------------

print("Running two full loops...")
check(
	Engine.runFor(4 * 3600, function()
		return twoLoopsDone
	end),
	"the loop runs Waiting -> Results -> Waiting twice"
)

for index, round in rounds do
	local entrants = round.playersLeft[1] or 0
	local byArena = 0
	for _, knockout in round.knockouts do
		if not knockout.by then
			byArena += 1
		end
	end
	local minutes = if round.resultsAt and round.activeAt then (round.resultsAt - round.activeAt) / 60 else -1
	print(
		string.format(
			"Round %d: %d Entrants, Active lasted %.1f min, winner %s, %d knockouts (%d by the arena)",
			index,
			entrants,
			minutes,
			tostring(round.winner),
			#round.knockouts,
			byArena
		)
	)
	check(round.resultsAt ~= nil, `round {index} reaches Results`)
	check(
		#round.knockouts == entrants - 1 or (#round.knockouts == entrants and round.winner == nil),
		`round {index}: everyone but the winner is knocked out`
	)
	check(round.feasts == 1, `round {index}: the Feast happens exactly once`)
	local shrinking = #round.collapse >= 1
	for i = 2, #round.collapse do
		if round.collapse[i] > round.collapse[i - 1] then
			shrinking = false
		end
	end
	check(shrinking, `round {index}: each Collapse stage is smaller than the last`)
	local countingDown = true
	for i = 2, #round.playersLeft do
		if round.playersLeft[i] > round.playersLeft[i - 1] then
			countingDown = false
		end
	end
	check(countingDown and round.playersLeft[#round.playersLeft] <= 1, `round {index}: players left counts down to one`)
end

local character = tester.Character
check(
	character ~= nil
		and math.abs(character.HumanoidRootPart.Position.X - Config.Lobby.CenterX) < Config.Lobby.Size / 2,
	"after Results the tester is back on the lobby platform"
)
check(Engine.workspace:FindFirstChild("Arena") == nil, "the arena is cleared between rounds")
check(Engine.bursts > 0, "knockouts emit particle bursts")

Engine.finish("rounds")
