-- [BoraRoad] traffic lamps: lane-driven protected movements and pedestrian clearance.
local Timing=require(script:WaitForChild('TrafficTiming'))
local colors={Red=Color3.fromRGB(255,52,39),Amber=Color3.fromRGB(255,184,35),Green=Color3.fromRGB(45,245,119),Left=Color3.fromRGB(45,245,119)}
local dark=Color3.fromRGB(21,25,24)
local function paintLamp(lamp,on,color)
	if not lamp then return end
	if lamp:IsA('BasePart') then
		lamp.Color=if on then color else dark
		lamp.Material=if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	else
		for _,piece in lamp:GetChildren() do if piece:IsA('BasePart') then
			piece.Color=if on then color else dark
			piece.Material=if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end end
	end
end
local function refresh()
	local roads=workspace:FindFirstChild('BoraRoads')
	local junctions=roads and roads:FindFirstChild('Junctions')
	if not junctions then return end
	local green=math.clamp(roads:GetAttribute('GreenSeconds') or 12,5,60)
	local left=math.clamp(roads:GetAttribute('LeftSeconds') or 8,4,40)
	local now=workspace:GetServerTimeNow()
	for _,junction in junctions:GetChildren() do
		local signals=junction:FindFirstChild('Signals')
		local pedestrians=junction:FindFirstChild('PedestrianSignals')
		local enabled=roads:GetAttribute('PedestrianSignals')~=false and roads:GetAttribute('Crosswalks')~=false
		local walk=if enabled and pedestrians and #pedestrians:GetChildren()>0 then math.clamp(roads:GetAttribute('WalkSeconds') or 10,6,60) else 0
		local flash=math.clamp(roads:GetAttribute('FlashSeconds') or 4,2,10)
		local approaches={}
		if signals then for _,signal in signals:GetChildren() do
			local arm,mask=signal:GetAttribute('Arm'),signal:GetAttribute('MovementMask')
			if arm and mask then table.insert(approaches,{Arm=arm,Mask=mask}) end
		end end
		local modern=#approaches>0
		local snapshot=Timing.snapshot(now,Timing.program(approaches),green,left,3,1.5,walk,flash)
		if modern then
			junction:SetAttribute('ActiveArm',snapshot.Arm or 0)
			junction:SetAttribute('ActiveMovement',snapshot.Movement)
			junction:SetAttribute('SignalStage',snapshot.Stage)
			junction:SetAttribute('CycleSeconds',snapshot.CycleSeconds)
		end
		if signals then for _,signal in signals:GetChildren() do
			local lamps
			if modern then
				lamps=Timing.lamps(snapshot,signal:GetAttribute('Arm') or 0,signal:GetAttribute('MovementMask') or 0)
			else
				local state=Timing.state(now,signal:GetAttribute('Phase') or 1,green,3,1.5,walk,flash)
				lamps={Red=state=='Red',Amber=state=='Amber',Green=state=='Green',Left=false}
			end
			local state=if lamps.Left then 'Left' elseif lamps.Green then 'Green' elseif lamps.Amber then 'Amber' else 'Red'
			if signal:GetAttribute('LightState')~=state then
				signal:SetAttribute('LightState',state)
				for name,color in colors do paintLamp(signal:FindFirstChild(name),lamps[name],color) end
			end
			for _,key in {'StraightAllowed','LeftAllowed','RightTurnAllowed','RightTurnMustYield'} do
				if signal:GetAttribute(key)~=lamps[key] then signal:SetAttribute(key,lamps[key]) end
			end
		end end
		if pedestrians then
			local state,lit
			if modern then state,lit=snapshot.Pedestrian,snapshot.WalkLit
			else state,lit=Timing.pedestrian(now,green,3,1.5,walk,flash) end
			local key=state..tostring(lit)
			for _,signal in pedestrians:GetChildren() do
				if signal:GetAttribute('DisplayState')~=key then
					signal:SetAttribute('DisplayState',key); signal:SetAttribute('LightState',state)
					for name,show in {StopIcon=state=='Red',WalkIcon=lit} do
						local icon=signal:FindFirstChild(name)
						if icon then for _,piece in icon:GetChildren() do if piece:IsA('BasePart') then piece.Transparency=if show then 0 else 1 end end end
					end
				end
			end
		end
	end
end
while true do refresh(); task.wait(.1) end
