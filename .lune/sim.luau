--!strict
-- Runs the headless simulations in tools/sim, each in its own Lune process.
-- Usage: lune run sim [scenario]   (arena, rounds or client)

local process = require("@lune/process")

local SCENARIOS = { "arena", "rounds", "client" }

local only = process.args[1]
local failures = 0
for _, name in SCENARIOS do
	if only == nil or only == name then
		print(`\n== {name}`)
		local result = process.exec("lune", { "run", `tools/sim/{name}.luau` }, { stdio = "inherit" })
		if not result.ok then
			failures += 1
		end
	end
end

print(if failures == 0 then "\nAll simulations passed" else `\n{failures} simulation(s) failed`)
process.exit(if failures == 0 then 0 else 1)
