-- [BoraVehicle] explicit entry/drive/exit lifecycle; no uploaded animation needed.
local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local Tween=game:GetService('TweenService')
local Replicated=game:GetService('ReplicatedStorage')
local D=require(script.VehicleDynamics)
local Physics=require(script.VehiclePhysics)({Vector3=Vector3,CFrame=CFrame},D)
local folder=workspace:WaitForChild('BoraVehicles')
local remote=Replicated:WaitForChild('BoraVehicleControl')
local sessions,players={},{}
local zero={Throttle=0,Steer=0,Brake=true}
local function setState(s,state)
	s.State=state;s.Car:SetAttribute('Lifecycle',state)
	for _,p in s.Car:GetDescendants() do if p:IsA('ProximityPrompt') then p.Enabled=state=='Empty' end end
	if s.Player and s.Player.Parent then remote:FireClient(s.Player,'State',s.Car,state) end
end
local function door(s,name,open)
	local motor=s.Car.Mechanics:FindFirstChild(name)
	if not motor then return end
	local sign=if name:sub(-1)=='L' then -1 else 1
	Tween:Create(motor,TweenInfo.new(.45,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),
		{C0=motor:GetAttribute('ClosedC0')*CFrame.Angles(0,if open then math.rad(65)*sign else 0,0)}):Play()
	motor:SetAttribute('Open',open)
end
local function restore(s)
	local saved=s.Saved
	if not saved then return end
	for motor,c0 in saved.Joints do if motor.Parent then motor.C0=c0 end end
	for part,collide in saved.Collision do if part.Parent then part.CanCollide=collide end end
	if saved.Animate and saved.Animate.Parent then saved.Animate.Disabled=saved.AnimateDisabled end
	if s.Humanoid and s.Humanoid.Parent then
		s.Humanoid.WalkSpeed=saved.WalkSpeed;s.Humanoid.JumpPower=saved.JumpPower;s.Humanoid.JumpHeight=saved.JumpHeight;s.Humanoid.AutoRotate=saved.AutoRotate
	end
	if s.CharacterRoot and s.CharacterRoot.Parent then s.CharacterRoot.Anchored=saved.Anchored end
	for _,ik in s.IK or {} do if ik.Parent then ik:Destroy() end end
	s.IK={};s.Saved=nil
end
local function cleanup(s)
	s.Token+=1
	if s.Death then s.Death:Disconnect();s.Death=nil end
	if s.Car.DriverSeat:FindFirstChild('SeatWeld') then s.Car.DriverSeat.SeatWeld:Destroy() end
	if s.Humanoid and s.Humanoid.Parent then s.Humanoid.Sit=false end
	local player=s.Player
	restore(s)
	s.Car.DriverSeat.Disabled=true;s.Car.Chassis.Anchored=true
	s.Car.Chassis.AssemblyLinearVelocity=Vector3.zero;s.Car.Chassis.AssemblyAngularVelocity=Vector3.zero
	if s.Physics and s.Physics.reset then s.Physics:reset() end
	s.Car.Driver.Value=nil;s.Input=zero;s.ExitPending=false
	for _,name in {'DoorFL','DoorFR','DoorRL','DoorRR'} do door(s,name,false) end
	setState(s,'Empty')
	if player then players[player]=nil end
	s.Player,s.Humanoid,s.CharacterRoot=nil,nil,nil
end
local function saveCharacter(s,character,humanoid,hrp)
	s.Humanoid,s.CharacterRoot=humanoid,hrp
	local head=character:FindFirstChild('Head')
	s.AvatarEyeHeight=if head then hrp.CFrame:PointToObjectSpace(head.Position).Y+head.Size.Y*.12 else .57*D.Scale
	s.Saved={Joints={},Collision={},WalkSpeed=humanoid.WalkSpeed,JumpPower=humanoid.JumpPower,JumpHeight=humanoid.JumpHeight,AutoRotate=humanoid.AutoRotate,Anchored=hrp.Anchored}
	local saved=s.Saved;saved.Animate=character:FindFirstChild('Animate')
	if saved.Animate and saved.Animate:IsA('LocalScript') then saved.AnimateDisabled=saved.Animate.Disabled;saved.Animate.Disabled=true else saved.Animate=nil end
	local animator=humanoid:FindFirstChildOfClass('Animator')
	if animator then for _,track in animator:GetPlayingAnimationTracks() do track:Stop(.15) end end
	for _,item in character:GetDescendants() do
		if item:IsA('BasePart') then saved.Collision[item]=item.CanCollide;item.CanCollide=false
		elseif item:IsA('Motor6D') then saved.Joints[item]=item.C0 end
	end
	humanoid.WalkSpeed,humanoid.JumpPower,humanoid.JumpHeight,humanoid.AutoRotate=0,0,0,false
	hrp.Anchored=true
end
local function pose(s,lean,step)
	for motor,c0 in s.Saved.Joints do
		local lower=motor.Name:lower()
		if lower=='waist' or lower=='rootjoint' then motor.C0=c0*CFrame.Angles(math.rad(lean),0,math.rad(-lean*.2))
		elseif lower=='lefthip' or lower=='left hip' then motor.C0=c0*CFrame.Angles(math.rad(step),0,0)
		elseif lower=='righthip' or lower=='right hip' then motor.C0=c0*CFrame.Angles(math.rad(-step*.5),0,0) end
	end
end
local function travel(s,frame,duration,token)
	local tween=Tween:Create(s.CharacterRoot,TweenInfo.new(duration,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{CFrame=frame})
	tween:Play();tween.Completed:Wait()
	return s.Token==token and s.Player and s.Player.Parent and s.Humanoid.Health>0
end
local function hands(s)
	local character=s.Player.Character
	for _,side in {'Left','Right'} do
		local arm,hand=character:FindFirstChild(side..'UpperArm'),character:FindFirstChild(side..'Hand')
		if arm and hand then
			local ik=Instance.new('IKControl');ik.Name='BoraDriving'..side
			ik.Type=Enum.IKControlType.Position;ik.ChainRoot,ik.EndEffector=arm,hand
			ik.Target=s.Car.Components.Steering.Pivot[side..'Grip'];ik.SmoothTime=.1;ik.Weight=1;ik.Parent=s.Humanoid
			table.insert(s.IK,ik)
		else
			local torso=character:FindFirstChild('Torso');local shoulder=torso and torso:FindFirstChild(side..' Shoulder')
			if shoulder then shoulder.C0=s.Saved.Joints[shoulder]*CFrame.Angles(math.rad(-70),0,0) end
		end
	end
end
local function enter(s,player)
	local character=player.Character;local humanoid=character and character:FindFirstChildOfClass('Humanoid');local hrp=character and character:FindFirstChild('HumanoidRootPart')
	if not humanoid or not hrp or players[player] then return end
	if not D.canEnter(s.State,s.Car.Chassis.AssemblyLinearVelocity.Magnitude,humanoid.Health>0,(hrp.Position-s.Car.Chassis.DriverHandle.WorldPosition).Magnitude) then return end
	s.Player=player;players[player]=s;s.Token+=1;local token=s.Token
	s.Car.Chassis.Anchored=true;s.Car.Driver.Value=player
	s.IK={};saveCharacter(s,character,humanoid,hrp)
	s.Death=humanoid.Died:Connect(function() cleanup(s) end)
	for _,name in {'DoorFR','DoorRL','DoorRR'} do door(s,name,false) end
	setState(s,'Entering');door(s,'DoorFL',true)
	task.wait(.45);if s.Token~=token then return end
	local root=s.Car.Chassis
	local outside=root.CFrame*root.OutsideDriver.CFrame
	local facing=CFrame.lookAt(outside.Position,Vector3.new(root.Position.X,outside.Position.Y,outside.Position.Z))
	pose(s,8,22)
	if not travel(s,facing,.45,token) then return end
	pose(s,25,65)
	local seatMarker=root.SeatedRoot.CFrame
	local seatY=math.clamp(root.Eye.Position.Y-s.AvatarEyeHeight,-.25*D.Scale,.32*D.Scale)
	local seated=root.CFrame*CFrame.new(seatMarker.Position.X,seatY,seatMarker.Position.Z)*seatMarker.Rotation
	if not travel(s,seated*CFrame.new(-.7,-.2,0),.45,token) then return end
	pose(s,12,80)
	if not travel(s,seated,.38,token) then return end
	for motor,c0 in s.Saved.Joints do if motor.Parent then motor.C0=c0 end end
	hrp.Anchored=false
	s.Car.DriverSeat.Disabled=false;s.Car.DriverSeat:Sit(humanoid)
	local weld=s.Car.DriverSeat:WaitForChild('SeatWeld',2)
	if s.Token~=token then return end
	if not weld or s.Car.DriverSeat.Occupant~=humanoid then cleanup(s);return end
	weld.C0=s.Car.DriverSeat.CFrame:ToObjectSpace(seated);weld.C1=CFrame.new()
	if s.Saved.Animate then s.Saved.Animate.Disabled=s.Saved.AnimateDisabled end
	hands(s);door(s,'DoorFL',false);task.wait(.5)
	if s.Token~=token then return end
	s.Car.Chassis.Anchored=true
	s.Car.Chassis.AssemblyLinearVelocity=Vector3.zero;s.Car.Chassis.AssemblyAngularVelocity=Vector3.zero
	if s.Physics and s.Physics.reset then s.Physics:reset() end
	s.LastInput=os.clock();s.Input=zero;setState(s,'Driving')
end
local function exit(s)
	if s.State~='Driving' then return end
	setState(s,'Exiting');s.Token+=1;local token=s.Token
	local root=s.Car.Chassis;root.Anchored=true;root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
	for _,ik in s.IK do ik:Destroy() end;s.IK={}
	if s.Saved.Animate then s.Saved.Animate.Disabled=true end
	local weld=s.Car.DriverSeat:FindFirstChild('SeatWeld');if weld then weld:Destroy() end
	s.Car.DriverSeat.Disabled=true;s.Humanoid.Sit=false;s.CharacterRoot.Anchored=true
	door(s,'DoorFL',true);task.wait(.45);if s.Token~=token then return end
	pose(s,25,65)
	local outside=root.CFrame*root.OutsideDriver.CFrame
	if not travel(s,outside*CFrame.Angles(0,math.pi/2,0),.65,token) then return end
	local ray=workspace:Raycast(outside.Position+Vector3.yAxis*5,Vector3.new(0,-20,0),s.Ray)
	local height=s.Humanoid.HipHeight+s.CharacterRoot.Size.Y*.5
	local destination=if ray then Vector3.new(outside.Position.X,ray.Position.Y+height+.1,outside.Position.Z) else outside.Position
	pose(s,0,0)
	if not travel(s,CFrame.new(destination)*root.CFrame.Rotation,.25,token) then return end
	cleanup(s)
end
local function register(car)
	if car:GetAttribute('AssetKind')~='BoraVehicle' or sessions[car] then return end
	local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude;ray.FilterDescendantsInstances={car};ray.RespectCanCollide=true
	local s={Car=car,State='Empty',Token=0,Input=zero,Ray=ray,LastInput=0,IK={}}
	s.Physics=Physics.new(car,workspace,ray);sessions[car]=s;car.Chassis.Anchored=true;car.DriverSeat.Disabled=true
	car.Destroying:Connect(function() if sessions[car] then cleanup(s);sessions[car]=nil end end)
	for _,name in {'DoorFL','DoorFR','DoorRL','DoorRR'} do
		local prompt=car.Components[name].Pivot.DoorPrompt.Interact
		prompt.Triggered:Connect(function(player)
			if name=='DoorFL' then task.spawn(function() local ok,err=pcall(enter,s,player);if not ok then warn('[BoraVehicle] entry',err);cleanup(s) end end)
			elseif s.State=='Empty' then
				local hrp=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
				if hrp and (hrp.Position-prompt.Parent.WorldPosition).Magnitude<=12 then door(s,name,not car.Mechanics[name]:GetAttribute('Open')) end
			end
		end)
	end
	car.DriverSeat:GetPropertyChangedSignal('Occupant'):Connect(function()
		if s.State=='Driving' and car.DriverSeat.Occupant~=s.Humanoid then cleanup(s) end
	end)
	setState(s,'Empty')
end
remote.OnServerEvent:Connect(function(player,action,car,data)
	local s=players[player]
	if not s or s.Car~=car or s.State~='Driving' or car.DriverSeat.Occupant~=s.Humanoid then return end
	if action=='Input' then
		if os.clock()-s.LastInput<1/120 then return end
		local valid=D.input(data);if not valid then return end
		s.Input=valid;s.LastInput=os.clock()
	elseif action=='Exit' then s.ExitPending=true;remote:FireClient(player,'Notice',car,'정지 후 하차합니다.') end
end)
Run.Heartbeat:Connect(function(dt)
	for car,s in sessions do
		if not car.Parent then cleanup(s);sessions[car]=nil;continue end
		if s.State=='Driving' then
			if s.Player.Character then s.Ray.FilterDescendantsInstances={car,s.Player.Character} end
			local input=if os.clock()-s.LastInput>.4 or s.ExitPending then zero else s.Input
			s.Physics:step(dt,input)
			local speed=car:GetAttribute('SpeedKmh') or 0
			car.DashboardDisplay.SpeedDisplay.Speed.Text=tostring(speed)..(if car:GetAttribute('NumericInstrumentSpeed') then '' else '  km/h')
			local gear=car.DashboardDisplay.SpeedDisplay:FindFirstChild('Gear')
			if gear then gear.Text=if input.Brake then 'P' elseif input.Throttle<0 then 'R' else 'D' end
			local center=car:FindFirstChild('CenterDisplay')
			if center then center.Infotainment.Status.Text=if input.Brake then '브레이크' elseif input.Throttle<0 then '후진 중' else '주행 중' end
			if s.ExitPending and D.exitReady(math.abs(s.Physics.Speed or 0)) then
				task.spawn(function() local ok,err=pcall(exit,s);if not ok then warn('[BoraVehicle] exit',err);cleanup(s) end end)
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(player) local s=players[player];if s then cleanup(s) end end)
for _,car in folder:GetChildren() do register(car) end
folder.ChildAdded:Connect(register)
