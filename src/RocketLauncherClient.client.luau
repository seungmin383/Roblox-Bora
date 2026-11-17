local Players=game:GetService('Players')
local Replicated=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer
local tool=script.Parent
local remote=Replicated:WaitForChild('BoraRocketFire',10);if not remote then return end
local mouse=player:GetMouse();local last=-math.huge
tool.Activated:Connect(function()
	if tool.Parent~=player.Character or os.clock()-last<1.13 then return end
	last=os.clock()
	remote:FireServer(mouse.Hit.Position)
end)
