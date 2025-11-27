--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Signal)

local localPlayer = Players.LocalPlayer
local MyCustomSignal = Signal.new() :: Signal.Identity<number, number>
local MyWrappedSignal = Signal.wrap(localPlayer.CharacterAdded) :: Signal.Identity<Model>

MyCustomSignal:Connect(function(a, b)
	print(a + b)
end)

MyWrappedSignal:Connect(function(character: Model)
	print(`El jugador ha reaparecido, nombre del model: {character.Name}`)
end)

task.spawn(function()
	while true do
		MyCustomSignal:Fire(15, 20)
		task.wait(0.5)
	end
end)
