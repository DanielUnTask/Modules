--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Signal)

local SignalWrapped = Signal.wrap(Players.PlayerAdded) :: Signal.Identity<Player>
local InternalSignal = Signal.new() :: Signal.Identity<...any>

SignalWrapped:Connect(function(player: Player)
	print(`El jugador {player.Name} - se ha unido!`)
	InternalSignal:Fire(player, function()
		player:SetAttribute("Coins", 15)
		print("Se agrego 15 monedas al jugador")
	end)
end)

InternalSignal:Connect(function(player, func)
	if player.Parent ~= Players then
		return
	end
	task.spawn(func)
end)
