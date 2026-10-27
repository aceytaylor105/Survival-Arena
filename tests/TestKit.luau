--!strict
-- Tiny assertion helpers for the Lune specs. Errors carry the caller's line.

local TestKit = {}

local function show(value: unknown): string
	if typeof(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

function TestKit.equal(actual: unknown, expected: unknown, message: string?)
	if actual ~= expected then
		error(`{message or "values differ"}: expected {show(expected)}, got {show(actual)}`, 2)
	end
end

function TestKit.near(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		error(`{message or "not within tolerance"}: expected {expected} ± {tolerance}, got {actual}`, 2)
	end
end

function TestKit.truthy(value: unknown, message: string?)
	if not value then
		error(message or `expected a truthy value, got {show(value)}`, 2)
	end
end

function TestKit.falsy(value: unknown, message: string?)
	if value then
		error(message or `expected a falsy value, got {show(value)}`, 2)
	end
end

return TestKit
