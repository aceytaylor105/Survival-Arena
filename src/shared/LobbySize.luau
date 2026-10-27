--!strict
-- Player count -> lobby size (Full Arena, Skirmish or Showdown). Pure rules: no Roblox globals.

local Config = require("./Config")

export type SizeName = "FullArena" | "Skirmish" | "Showdown"
export type Size = {
	MinPlayers: number,
	MaxPlayers: number,
	ArenaRadius: number,
	CollapseStages: number,
}

local LobbySize = {}

-- Smallest first.
LobbySize.Names = table.freeze({ "Showdown", "Skirmish", "FullArena" } :: { SizeName })

function LobbySize.get(name: SizeName): Size
	return Config.LobbySizes[name]
end

-- Returns the size whose player range holds `playerCount`, or nil when no round can start
-- with that many (below the smallest size, above the largest, or not a whole number).
function LobbySize.pick(playerCount: number): (SizeName?, Size?)
	if playerCount ~= playerCount or playerCount % 1 ~= 0 then
		return nil, nil
	end
	for _, name in LobbySize.Names do
		local size = LobbySize.get(name)
		if playerCount >= size.MinPlayers and playerCount <= size.MaxPlayers then
			return name, size
		end
	end
	return nil, nil
end

return table.freeze(LobbySize)
