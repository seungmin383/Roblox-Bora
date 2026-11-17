local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local hub=workspace:WaitForChild("CentralHub_Stage5")
local header=hub:WaitForChild("02_CardinalEntrances"):WaitForChild("East_Sea"):WaitForChild("GatewayHeader")
local character=player.Character or player.CharacterAdded:Wait()
local hrp=character:WaitForChild("HumanoidRootPart")
local humanoid=character:WaitForChild("Humanoid")
task.wait(.15)
if (Vector2.new(hrp.Position.X,hrp.Position.Z)).Magnitude<=56 then
 local camera=workspace.CurrentCamera
 local direction=Vector3.new(header.Position.X-hrp.Position.X,0,header.Position.Z-hrp.Position.Z).Unit
 camera.CameraSubject=humanoid
 camera.CameraType=Enum.CameraType.Scriptable
 camera.CFrame=CFrame.lookAt(hrp.Position-direction*16+Vector3.new(0,8,0),hrp.Position+direction*12+Vector3.new(0,2,0))
 task.wait(.12)
 camera.CameraType=Enum.CameraType.Custom
end