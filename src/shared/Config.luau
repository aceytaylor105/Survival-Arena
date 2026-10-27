--!strict
-- Every tunable number lives here. Starting values; tune in playtests.
local Config = {
	Queue = {
		WaitSeconds = 60, -- start with whoever is queued after this
		MinPlayers = 2,
		MaxPlayers = 24,
		CheckSeconds = 0.5, -- how often the queue recounts the lobby
	},

	-- Chosen by LobbySize.luau from the human player count
	LobbySizes = {
		FullArena = { MinPlayers = 12, MaxPlayers = 24, ArenaRadius = 450, CollapseStages = 6 },
		Skirmish = { MinPlayers = 6, MaxPlayers = 11, ArenaRadius = 300, CollapseStages = 5 },
		Showdown = { MinPlayers = 2, MaxPlayers = 5, ArenaRadius = 150, CollapseStages = 3 },
	},

	Round = {
		CountdownSeconds = 20,
		ResultsSeconds = 15,
		FeastAtPlayersLeft = 5,
		SpawnRingFraction = 0.35, -- pads sit on a ring at this share of ArenaRadius
		CheckSeconds = 0.25, -- how often the Active phase checks for a winner
		LivingEntrantTag = "LivingEntrant", -- tag on living Entrants' characters
	},

	Collapse = {
		StageSeconds = 90,
		FinalRadius = 30,
		DamagePerSecondOutside = 5,
		UpdateSeconds = 0.25, -- how often the wall moves and outside damage applies
		WallSegments = 48,
		WallHeight = 80,
		WallThickness = 1,
		WallTransparency = 0.55,
	},

	Survival = {
		MaxHealth = 100,
		MaxHunger = 100,
		HungerDrainPerSecond = 0.25, -- empty after about 6.7 minutes
		StarvingDamagePerSecond = 1,
		-- Hunger each food restores when eaten.
		FoodRestores = { Berries = 20, Bread = 40, FeastBasket = 100 },
		TickSeconds = 0.5, -- how often the server applies hunger and sends stats
	},

	Weapons = {
		Spear = { Damage = 25, Range = 10, Cooldown = 0.8 },
		Axe = { Damage = 35, Range = 7, Cooldown = 1.1 },
		Bow = { Damage = 30, Range = 150, Cooldown = 1.5 },
	},

	Combat = {
		MeleeArcDegrees = 70, -- melee hits targets within this angle of the aim direction
		EyeHeight = 1.5, -- attacks start this far above the attacker's root part
		HitFlashSeconds = 0.15,
		TracerSeconds = 0.15, -- how long a bow shot's line stays visible
		TracerWidth = 0.3,
		KnockoutParticles = 40, -- size of the stylized burst on a knockout
		KnockoutEffectSeconds = 2,
	},

	Loot = {
		TierWeights = { Common = 70, Rare = 25, Epic = 5 },
		SpireTierWeights = { Common = 30, Rare = 50, Epic = 20 },
		CratesPerPlayer = 3,
		ItemsPerCrate = { Common = 1, Rare = 2, Epic = 3 },
		-- Item weights within each tier. Items are Weapons or Survival.FoodRestores entries.
		TierItems = {
			Common = { Berries = 3, Spear = 2 },
			Rare = { Axe = 2, Bow = 1, Bread = 2 },
			Epic = { Axe = 1, Bow = 2, FeastBasket = 2 },
		},
		OpenSeconds = 0.5, -- hold time on a crate's prompt
		Reach = 10, -- prompt distance from an Entrant to a crate
		ReachSlack = 3, -- extra distance the server allows when it re-checks the reach
		FeastCrates = 5, -- epic crates that appear at the Spire for the Feast
	},

	Bots = {
		EnabledInStudio = true, -- lets one person test a full round
		EnabledLive = false,
		FillTo = 8,
		ThinkSeconds = 0.4,
		AggroRange = 60, -- armed bots go after Entrants this close
		HungryBelow = 50, -- bots eat when hunger drops under this
		AimSpreadDegrees = 6, -- bow inaccuracy, so bots aren't perfect shots
		BorderMargin = 10, -- bots keep this far inside the radius the border is closing to
		ArriveDistance = 4, -- a wandering bot picks a new spot when this close to the last
		StuckDistance = 1, -- a bot that moves less than this in a think, while it wants to move...
		StuckThinks = 3, -- ...this many thinks in a row jumps and sidesteps
		SidestepDistance = 10,
		IdleBelowSpeed = 0.1, -- bots slower than this play the idle animation
		RunAnimationSpeed = 12, -- bots moving faster than this play the run animation, slower the walk
		AnimationFadeSeconds = 0.2,
	},

	-- Greybox map dimensions in studs, used by ArenaBuilder. The arena is centered on the origin.
	Arena = {
		FloorThickness = 4,
		SpireBaseRadius = 16,
		SpireBaseHeight = 1, -- low enough to walk onto
		SpireWidth = 10,
		SpireHeight = 70,
		PadDiameter = 8,
		PadHeight = 1,
		SpawnHeight = 4, -- characters are placed this far above a pad's top
		CrateSize = 4,
		SpireCrateShare = 0.25, -- this share of a round's crates ring the Supply Spire
		SpireCrateRingGap = 6, -- Spire crates sit this far outside the Spire base
		CrateEdgeMargin = 15, -- scattered crates keep this far inside the arena edge
		CratePadClearance = 10, -- and this far from spawn pads
		CratePlacementTries = 12,
	},

	Lobby = {
		CenterX = 750, -- the lobby platform sits beside the arena, at ground level
		Size = 100,
		WallHeight = 12,
		SpawnFraction = 0.6, -- players spawn within this share of the platform
		RespawnSeconds = 3, -- after falling or resetting in the lobby
	},

	Inventory = {
		Slots = 6,
	},

	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 24,
	},

	Input = {
		AimDistance = 500, -- how far the client looks for an aim point under the cursor or crosshair
	},

	-- HUD sizes in pixels.
	Hud = {
		Padding = 12,
		TextSize = 18,
		TitleTextSize = 26,
		SmallTextSize = 14,
		TinyTextSize = 12,
		CornerRadius = 6,
		SlotStroke = 1,
		SelectedSlotStroke = 3,
		BarWidth = 220,
		BarHeight = 18,
		SlotSize = 56,
		TouchButtonSize = 76, -- big enough for a thumb on a phone
		SpectateButtonSize = 56,
		KillFeedLines = 4,
		KillFeedSeconds = 6,
		BannerSeconds = 4,
		BorderWarningDistance = 15, -- warn when this close to the border
		PanelTransparency = 0.35,
		TextStrokeTransparency = 0.6, -- outline that keeps text readable over the world
		RefreshSeconds = 0.1,
		CoreGuiRetries = 20, -- StarterGui:SetCore can fail until the core scripts load
		CoreGuiRetrySeconds = 0.5,
	},

	Remotes = {
		MaxRequestsPerSecond = 10, -- per player, per remote; extra requests are dropped
		AimTolerance = 0.01, -- an aim direction's length must be within 1 +/- this
	},

	-- Flat greybox colors, RGB 0-255.
	Colors = {
		Floor = { 118, 138, 104 },
		Spire = { 236, 226, 198 },
		SpireBase = { 196, 186, 160 },
		Pad = { 86, 108, 160 },
		Lobby = { 150, 150, 160 },
		LobbyWall = { 110, 110, 122 },
		CommonCrate = { 160, 120, 80 },
		RareCrate = { 70, 130, 210 },
		EpicCrate = { 170, 90, 210 },
		Tracer = { 255, 240, 180 },
		HitFlash = { 255, 255, 255 },
		KnockoutBurst = { 255, 210, 90 },
		CollapseWall = { 235, 95, 60 },
		Panel = { 20, 22, 28 },
		Text = { 245, 245, 245 },
		Health = { 220, 70, 70 },
		Hunger = { 230, 170, 60 },
		Warning = { 255, 110, 80 },
		Danger = { 255, 60, 60 },
		SelectedSlot = { 255, 220, 120 },
	},
}

return table.freeze(Config)
