--!strict
-- Every tunable number lives here. Starting values; tune in playtests.
local Config = {
	Queue = {
		WaitSeconds = 60, -- start with whoever is queued after this
		MinPlayers = 2,
		MaxPlayers = 24,
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
}

return table.freeze(Config)
