-- [BoraVehicle] local controls, first-person cockpit and lifecycle HUD.
local Players=game:GetService('Players')
local CAS=game:GetService('ContextActionService')
local UIS=game:GetService('UserInputService')
local Run=game:GetService('RunService')
local remote=game:GetService('ReplicatedStorage'):WaitForChild('BoraVehicleControl')
local player=Players.LocalPlayer
local car,state,first=nil,'Empty',false
local pressed={};local previous;local yaw,pitch=0,0;local sendTime=0;local inputDirty=true
local transparent={}
local gui=Instance.new('ScreenGui');gui.Name='BoraVehicleHUD';gui.ResetOnSpawn=false;gui.Enabled=false;gui.Parent=player:WaitForChild('PlayerGui')
local panel=Instance.new('Frame');panel.Size=UDim2.fromOffset(390,88);panel.Position=UDim2.new(.5,-195,1,-115);panel.BackgroundColor3=Color3.fromRGB(23,29,35);panel.BackgroundTransparency=.15;panel.Parent=gui
local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,10);corner.Parent=panel
local speed=Instance.new('TextLabel');speed.Size=UDim2.new(1,-20,0,37);speed.Position=UDim2.fromOffset(10,4);speed.BackgroundTransparency=1;speed.TextColor3=Color3.fromRGB(222,241,250);speed.TextSize=27;speed.Font=Enum.Font.GothamMedium;speed.Text='BORA Sedan';speed.Parent=panel
local hint=speed:Clone();hint.Name='Controls';hint.Size=UDim2.new(1,-20,0,39);hint.Position=UDim2.fromOffset(10,43);hint.TextSize=13;hint.TextWrapped=true;hint.Text='W/S 전진·후진   A/D 조향   Space 브레이크\nV 1·3인칭 전환   E 정차 후 하차';hint.Parent=panel
local notice=''
local function resetVisibility()
	for part,value in transparent do if part.Parent then part.LocalTransparencyModifier=value end end
	table.clear(transparent)
end
local function cockpitVisibility()
	local character=player.Character;if not character then return end
	for _,item in character:GetDescendants() do
		if item:IsA('BasePart') and (item.Name=='Head' or item:FindFirstAncestorOfClass('Accessory')) then
			if transparent[item]==nil then transparent[item]=item.LocalTransparencyModifier end
			item.LocalTransparencyModifier=1
		end
	end
end
local function cameraMode()
	local camera=workspace.CurrentCamera
	resetVisibility()
	if not camera or not previous then return end
	if first and state=='Driving' then
		camera.CameraType=Enum.CameraType.Scriptable;camera.FieldOfView=78
		UIS.MouseBehavior=Enum.MouseBehavior.LockCenter;UIS.MouseIconEnabled=false
	else
		camera.CameraType=Enum.CameraType.Custom;camera.CameraSubject=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
		camera.FieldOfView=72;player.CameraMinZoomDistance=8;player.CameraMaxZoomDistance=35
		UIS.MouseBehavior=Enum.MouseBehavior.Default;UIS.MouseIconEnabled=true
	end
end
local function unbind()
	for _,key in {'Forward','Reverse','Left','Right','Brake','Exit','Camera'} do CAS:UnbindAction('BoraVehicle'..key) end
	pressed={};inputDirty=true;sendTime=0;resetVisibility()
	if previous then
		local camera=workspace.CurrentCamera
		player.CameraMinZoomDistance,player.CameraMaxZoomDistance=previous.Min,previous.Max
		player.CameraMode=previous.Mode
		if camera then camera.CameraType=Enum.CameraType.Custom;camera.CameraSubject=player.Character and player.Character:FindFirstChildOfClass('Humanoid');camera.FieldOfView=previous.FOV end
		UIS.MouseBehavior,UIS.MouseIconEnabled=previous.Mouse,previous.Cursor
		previous=nil
	end
	car,state,first=nil,'Empty',false;gui.Enabled=false
end
local function action(name,inputState)
	local key=name:gsub('^BoraVehicle','')
	local down=inputState==Enum.UserInputState.Begin
	if inputState==Enum.UserInputState.Begin or inputState==Enum.UserInputState.End or inputState==Enum.UserInputState.Cancel then
		if pressed[key]~=down then inputDirty=true end
		pressed[key]=down
	end
	if state=='Driving' and down then
		if key=='Exit' then remote:FireServer('Exit',car)
		elseif key=='Camera' then first=not first;yaw,pitch=0,0;cameraMode() end
	end
	return Enum.ContextActionResult.Sink
end
local function bind()
	for _,spec in {{'Forward',Enum.KeyCode.W,Enum.KeyCode.Up},{'Reverse',Enum.KeyCode.S,Enum.KeyCode.Down},
		{'Left',Enum.KeyCode.A,Enum.KeyCode.Left},{'Right',Enum.KeyCode.D,Enum.KeyCode.Right},
		{'Brake',Enum.KeyCode.Space},{'Exit',Enum.KeyCode.E},{'Camera',Enum.KeyCode.V}} do
		CAS:BindActionAtPriority('BoraVehicle'..spec[1],action,true,3000,table.unpack(spec,2))
		CAS:SetTitle('BoraVehicle'..spec[1],({Forward='가속',Reverse='후진',Left='◀',Right='▶',Brake='제동',Exit='하차',Camera='시점'})[spec[1]])
	end
	for _,spec in {{'Forward',.88,.55},{'Reverse',.88,.75},{'Left',.05,.70},{'Right',.20,.70},{'Brake',.72,.75},{'Exit',.05,.20},{'Camera',.20,.20}} do
		CAS:SetPosition('BoraVehicle'..spec[1],UDim2.fromScale(spec[2],spec[3]))
	end
end
remote.OnClientEvent:Connect(function(kind,vehicle,value)
	if kind=='Notice' and car==vehicle then notice=value;return end
	if kind~='State' then return end
	if value=='Empty' then if car==vehicle then unbind() end;return end
	if not previous then
		local camera=workspace.CurrentCamera
		previous={Min=player.CameraMinZoomDistance,Max=player.CameraMaxZoomDistance,Mode=player.CameraMode,FOV=camera.FieldOfView,Mouse=UIS.MouseBehavior,Cursor=UIS.MouseIconEnabled}
		player.CameraMode=Enum.CameraMode.Classic;bind()
	end
	car,state=vehicle,value;gui.Enabled=true;notice='';inputDirty=true;sendTime=.05
	if state~='Driving' then first=false;cameraMode() else cameraMode() end
end)
UIS.WindowFocusReleased:Connect(function() pressed={};inputDirty=true end)
player.CharacterRemoving:Connect(unbind)
Run:BindToRenderStep('BoraVehicleCamera',Enum.RenderPriority.Camera.Value+1,function(dt)
	if not car then return end
	if not car.Parent then unbind();return end
	if state=='Driving' then
		speed.Text=tostring(car:GetAttribute('SpeedKmh') or 0)..'  km/h'
		hint.Text=if notice~='' then notice else 'W/S 전진·후진   A/D 조향   Space 브레이크\nV 1·3인칭 전환   E 정차 후 하차'
		sendTime+=dt
		if sendTime>=1/60 and (inputDirty or sendTime>=.05) then
			sendTime=0;inputDirty=false
			remote:FireServer('Input',car,{Throttle=(if pressed.Forward then 1 else 0)-(if pressed.Reverse then 1 else 0),
				Steer=(if pressed.Right then 1 else 0)-(if pressed.Left then 1 else 0),Brake=pressed.Brake==true})
		end
		if first then
			local delta=UIS:GetMouseDelta();yaw=math.clamp(yaw-delta.X*.0025,-math.rad(100),math.rad(100));pitch=math.clamp(pitch-delta.Y*.0025,-math.rad(48),math.rad(38))
			workspace.CurrentCamera.CFrame=car.Chassis.CFrame*car.Chassis.Eye.CFrame*CFrame.Angles(0,yaw,0)*CFrame.Angles(pitch,0,0)
			cockpitVisibility()
		end
	else
		speed.Text=if state=='Entering' then '탑승 중' else '하차 중'
		hint.Text='문을 통과하는 동안 잠시 기다려 주세요.'
	end
end)
