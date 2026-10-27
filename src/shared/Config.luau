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
	},

	Collapse = {
		StageSeconds = 90,
		FinalRadius = 30,
		DamagePerSecondOutside = 5,
	},

	Survival = {
		MaxHealth = 100,
		MaxHunger = 100,
		HungerDrainPerSecond = 0.25, -- empty after about 6.7 minutes
		StarvingDamagePerSecond = 1,
	},

	Weapons = {
		Spear = { Damage = 25, Range = 10, Cooldown = 0.8 },
		Axe = { Damage = 35, Range = 7, Cooldown = 1.1 },
		Bow = { Damage = 30, Range = 150, Cooldown = 1.5 },
	},

	Loot = {
		TierWeights = { Common = 70, Rare = 25, Epic = 5 },
		SpireTierWeights = { Common = 30, Rare = 50, Epic = 20 },
		CratesPerPlayer = 3,
	},

	Bots = {
		EnabledInStudio = true, -- lets one person test a full round
		EnabledLive = false,
		FillTo = 8,
	},

	-- Greybox map dimensions in studs, used by ArenaBuilder. The arena is centered on the origin.
	Arena = {
		FloorThickness = 4,
		SpireBaseRadius = 16,
		SpireBaseHeight = 2,
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
	},
}

return table.freeze(Config)
