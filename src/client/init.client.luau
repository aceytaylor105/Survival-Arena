--!strict
-- Starts the client controllers. The client only shows state and sends intent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local HudController = require(script.HudController)
local InputController = require(script.InputController)
local SpectateController = require(script.SpectateController)

-- No tools backpack (the HUD shows the inventory), no default health bar (health lives on
-- the server, not in the Humanoid), and no reset button (knockouts belong to the server).
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
task.spawn(function()
	for _ = 1, Config.Hud.CoreGuiRetries do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			return
		end
		task.wait(Config.Hud.CoreGuiRetrySeconds)
	end
end)

InputController.start()
HudController.start()
SpectateController.start()
