--!strict
-- Runs every tests/*.spec.luau. Each spec returns a function that registers tests:
--   return function(test) test("name", function() ... end) end
-- Usage: lune run test [filter]   (filter matches spec file names)

local fs = require("@lune/fs")
local process = require("@lune/process")

type Test = { name: string, fn: () -> () }

local filter = process.args[1]

local specNames = {}
for _, name in fs.readDir("tests") do
	if string.match(name, "%.spec%.luau$") and (filter == nil or string.find(name, filter, 1, true)) then
		table.insert(specNames, name)
	end
end
table.sort(specNames)

local passed, failed = 0, 0

for _, fileName in specNames do
	local specName = string.gsub(fileName, "%.luau$", "")
	print(specName)

	local loaded, register = pcall(require, "../tests/" .. specName)
	if not loaded or typeof(register) ~= "function" then
		failed += 1
		print(`  FAIL could not load spec: {if loaded then "spec must return a function" else register}`)
		continue
	end

	local tests: { Test } = {}
	register(function(name: string, fn: () -> ())
		table.insert(tests, { name = name, fn = fn })
	end)

	for _, t in tests do
		local ok, err = pcall(t.fn)
		if ok then
			passed += 1
			print(`  ok   {t.name}`)
		else
			failed += 1
			print(`  FAIL {t.name}\n       {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed, {#specNames} spec file(s)`)
process.exit(if failed == 0 then 0 else 1)
