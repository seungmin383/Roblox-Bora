local Players=game:GetService('Players');local Input=game:GetService('UserInputService');local Run=game:GetService('RunService')
local player=Players.LocalPlayer;local remote=game:GetService('ReplicatedStorage'):WaitForChild('BoraBuildingElevator')
local gui=Instance.new('ScreenGui');gui.Name='BoraElevatorFloors';gui.ResetOnSpawn=false;gui.Enabled=false;gui.Parent=player:WaitForChild('PlayerGui')
local frame=Instance.new('Frame');frame.AnchorPoint=Vector2.new(.5,.5);frame.Position=UDim2.fromScale(.5,.5);frame.Size=UDim2.new(.8,0,0,410)
frame.BackgroundColor3=Color3.fromRGB(30,38,40);frame.Parent=gui
local constraint=Instance.new('UISizeConstraint');constraint.MaxSize=Vector2.new(360,410);constraint.Parent=frame
local title=Instance.new('TextLabel');title.Size=UDim2.new(1,-60,0,48);title.Position=UDim2.fromOffset(14,0);title.BackgroundTransparency=1
title.Text,title.TextColor3,title.TextSize,title.Font='이동할 층 선택',Color3.new(1,1,1),22,Enum.Font.SourceSansBold;title.Parent=frame
local close=Instance.new('TextButton');close.Text='닫기';close.Position=UDim2.new(1,-60,0,10);close.Size=UDim2.fromOffset(50,30);close.Parent=frame
local list=Instance.new('ScrollingFrame');list.Position=UDim2.fromOffset(14,54);list.Size=UDim2.new(1,-28,1,-68);list.BackgroundTransparency=1;list.BorderSizePixel=0;list.ScrollBarThickness=5;list.Parent=frame
local layout=Instance.new('UIGridLayout');layout.CellSize=UDim2.new(1/3,-6,0,50);layout.CellPadding=UDim2.fromOffset(6,6);layout.Parent=list
local target=nil
local function hide() gui.Enabled=false;target=nil end
close.MouseButton1Click:Connect(hide)
Input.InputBegan:Connect(function(input) if input.KeyCode==Enum.KeyCode.Escape then hide() end end)
player.CharacterRemoving:Connect(hide)
remote.OnClientEvent:Connect(function(action,model,floors,current)
	if action~='Open' or not model or not model:IsDescendantOf(workspace) then return end
	for _,child in list:GetChildren() do if child:IsA('TextButton') then child:Destroy() end end
	target=model
	for floor=1,math.clamp(floors,2,24) do
		local b=Instance.new('TextButton');b.Text=floor..'층'..(if floor==current then ' · 현재' else '');b.TextColor3=Color3.new(1,1,1)
		b.BackgroundColor3=if floor==current then Color3.fromRGB(83,132,108) else Color3.fromRGB(59,74,78)
		b.TextSize,b.Font,b.LayoutOrder,b.Parent=18,Enum.Font.SourceSansBold,floor,list
		b.MouseButton1Click:Connect(function() if target then remote:FireServer(target,floor) end;hide() end)
	end
	list.CanvasSize=UDim2.fromOffset(0,math.ceil(floors/3)*56);gui.Enabled=true
end)
Run.Heartbeat:Connect(function()
	if not target then return end
	local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
	local cab=target.Parent and target:FindFirstChild('Cab');local origin=cab and cab:FindFirstChild('CabRoot')
	if not root or not origin or (root.Position-origin.Position).Magnitude>16 then hide() end
end)
