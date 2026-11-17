return function(api,B)
	local I,V,C,E,Color=api.Instance,api.Vector3,api.CFrame,api.Enum,api.Color3;local S=1/.28;local F={}
	local function model(parent,name) local m=I.new('Model');m.Name,m.Parent=name,parent;return m end
	local function part(parent,base,name,size,pos,color,collide)
		local p=I.new('Part');p.Name,p.Size,p.CFrame=name,V.new(table.unpack(size))*S,base*C.new(V.new(table.unpack(pos))*S)
		p.Anchored,p.CanCollide,p.CanQuery,p.CanTouch=true,collide~=false,collide~=false,false
		p.Color=Color.fromRGB(table.unpack(color or {215,211,199}));p.Material=E.Material.SmoothPlastic
		p.TopSurface,p.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth;p.Parent=parent;return p
	end
	local function prompt(parent,name,text)
		local p=I.new('ProximityPrompt');p.Name,p.ActionText,p.ObjectText=name,text,'엘리베이터'
		p.KeyboardKeyCode,p.HoldDuration,p.MaxActivationDistance=E.KeyCode.E,0,8;p.Parent=parent
	end
	local function display(parent)
		local gui=I.new('SurfaceGui');gui.Name='Display';gui.Face=E.NormalId.Front;gui.CanvasSize=api.Vector2.new(240,130);gui.Parent=parent
		local t=I.new('TextLabel');t.Name='FloorText';t.Size=api.UDim2.fromScale(1,1);t.BackgroundTransparency=1
		t.Text,t.TextColor3,t.TextScaled,t.Font='1층',Color.fromRGB(237,228,195),true,E.Font.SourceSansBold;t.Parent=gui
	end
	local function stair(parent,p,e,base,continued)
		local root=model(parent,'Stairs_'..e.Id);root:SetAttribute('PlanId',e.Id);root:SetAttribute('FromFloor',e.Floor)
		local y,h=B.level(p,e.Floor),B.height(p,e.Floor);local n=math.ceil(h/.36);local rise=h/(2*n)
		local frame=base*C.new(e.X*S,y*S,e.Z*S)*C.Angles(0,math.rad(e.Rotation),0);local tread=3.7/n
		-- A full-height block below each step blocks the flight on the storey below
		-- when stairs are stacked. A closed riser only needs to reach the previous tread.
		for i=1,n do
			local thickness=rise+.04
			part(root,frame,'LowerTread',{1.28,thickness,tread},{-.73,i*rise-thickness*.5,-2.4+(i-.5)*tread})
			part(root,frame,'UpperTread',{1.28,thickness,tread},{.73,h*.5+i*rise-thickness*.5,1.3-(i-.5)*tread})
		end
		part(root,frame,'MidLanding',{3,.16,1.1},{0,h*.5-.08,1.85})
		part(root,frame,'MidBackGuard',{3,1,.055},{0,h*.5+.5,2.37},{83,96,94})
		local function rail(x,z0,z1,y0,y1)
			local a,b=V.new(x,y0,z0)*S,V.new(x,y1,z1)*S
			local r=part(root,C.new(),'Handrail',{.045,.045,(b-a).Magnitude/S},{0,0,0},{83,96,94},false)
			r.CFrame=frame*C.lookAt((a+b)*.5,b)
			for i=0,5 do local t=i/5;part(root,frame,'RailPost',{.035,.9,.035},{x,y0+(y1-y0)*t-.45,z0+(z1-z0)*t},{83,96,94},false) end
		end
		rail(-1.43,-2.35,1.3,rise+.95,h*.5+.95);rail(1.43,1.3,-2.35,h*.5+rise+.95,h+.95)
		for _,x in {-1.43,1.43} do part(root,frame,'UpperOpeningGuard',{.045,1,4.75},{x,h+.5,0},{83,96,94}) end
		part(root,frame,'UpperBackGuard',{2.85,1,.045},{0,h+.5,2.37},{83,96,94})
		-- The left half of the front edge is a drop at the arrival floor unless
		-- the next staircase begins there. The right half is the arrival path.
		if not continued then part(root,frame,'UpperFrontGuard',{1.44,1,.055},{-.72,h+.5,-2.37},{83,96,94}) end
	end
	local function elevator(parent,p,e,base)
		local root=model(parent,'Elevator_'..e.Id);root:SetAttribute('BoraElevator',true);root:SetAttribute('PlanId',e.Id);root:SetAttribute('Floors',p.Floors)
		local frame=base*C.new(e.X*S,0,e.Z*S)*C.Angles(0,math.rad(e.Rotation),0)
		local origin=part(root,frame,'ShaftOrigin',{.04,.04,.04},{0,0,0},nil,false);origin.Transparency=1;origin.Locked=true
		local stops=I.new('Folder');stops.Name,stops.Parent='Stops',root
		local landings=model(root,'Landings');local h=B.level(p,p.Floors)+B.height(p,p.Floors)
		for _,x in {-1.32,1.32} do part(root,frame,'ShaftSide',{.16,h,2.8},{x,h*.5,0},{191,194,190}) end
		part(root,frame,'ShaftBack',{2.48,h,.16},{0,h*.5,1.32},{191,194,190})
		for floor=1,p.Floors do
			local y,height=B.level(p,floor),B.height(p,floor)
			local stop=I.new('NumberValue');stop.Name,stop.Value,stop.Parent='Floor_'..floor,y*S,stops
			local landing=model(landings,'Floor_'..floor);landing:SetAttribute('Floor',floor)
			for _,side in {-1,1} do
				part(landing,frame,'DoorPier',{.75,height,.16},{side*1.025,y+height*.5,-1.32})
				local door=part(landing,frame,if side<0 then 'DoorLeft' else 'DoorRight',{.65,2.3,.075},{side*.325,y+1.15,-1.365},{148,158,157})
				door:SetAttribute('DoorSide',side)
			end
			part(landing,frame,'DoorLintel',{1.3,height-2.3,.16},{0,y+(height+2.3)*.5,-1.32})
			part(landing,frame,'LandingThreshold',{1.3,.12,.37},{0,y-.06,-1.315},{151,158,152})
			local call=part(landing,frame,'CallButton',{.16,.27,.06},{.96,y+1.20,-1.435},{75,91,87},false)
			prompt(call,'Call','호출 · '..floor..'층')
		end
		local cab=model(root,'Cab');local cabRoot=part(cab,frame,'CabRoot',{.04,.04,.04},{0,0,0},nil,false);cabRoot.Transparency=1;cab.PrimaryPart=cabRoot
		part(cab,frame,'CabFloor',{2.18,.14,2.25},{0,-.07,0},{126,133,128})
		part(cab,frame,'CabCeiling',{2.18,.10,2.25},{0,2.39,0},{224,225,211})
		for _,x in {-1.06,1.06} do part(cab,frame,'CabSide',{.06,2.34,2.25},{x,1.17,0},{172,181,176}) end
		part(cab,frame,'CabBack',{2.06,2.34,.06},{0,1.17,1.095},{172,181,176})
		for _,x in {-.835,.835} do part(cab,frame,'CabFrontPier',{.39,2.34,.06},{x,1.17,-1.105},{172,181,176}) end
		for _,side in {-1,1} do
			local door=part(cab,frame,if side<0 then 'DoorLeft' else 'DoorRight',{.64,2.3,.045},{side*.32,1.15,-1.105},{145,157,153})
			door:SetAttribute('DoorSide',side)
		end
		local panel=part(cab,frame,'ControlPanel',{.22,.42,.045},{.78,1.36,1.045},{50,64,60},false)
		prompt(panel,'SelectFloor','층 선택');display(panel)
	end
	function F.create(parent,p,plan,base)
		local root=model(parent,'FloorPlanInterior')
		for _,e in plan.Items do
			local y,h=B.level(p,e.Floor),B.height(p,e.Floor)
			if e.Kind=='Wall' then
				local a,b=V.new(e.X,y,e.Z)*S,V.new(e.X2,y,e.Z2)*S
				local frame=base*C.lookAt(a,b);local length=B.wallLength(e)
				local start,finish=B.doorSpan(e)
				if not start then
					local wall=part(root,frame,'PlanWall_'..e.Id,{e.Thickness,h,length},{0,h*.5,-length*.5})
					wall:SetAttribute('PlanId',e.Id);wall:SetAttribute('Floor',e.Floor)
				else
					local wall=model(root,'PlanWall_'..e.Id);wall:SetAttribute('PlanId',e.Id);wall:SetAttribute('Floor',e.Floor)
					part(wall,frame,'WallStart',{e.Thickness,h,start},{0,h*.5,-start*.5})
					part(wall,frame,'WallEnd',{e.Thickness,h,length-finish},{0,h*.5,-(length+finish)*.5})
					part(wall,frame,'DoorHeader',{e.Thickness,h-B.DoorHeight,B.DoorWidth},{0,(h+B.DoorHeight)*.5,-(start+finish)*.5})
					local trim={109,85,62}
					for _,edge in {start+.023,finish-.023} do
						part(wall,frame,'DoorJamb',{e.Thickness+.035,B.DoorHeight,.046},{0,B.DoorHeight*.5,-edge},trim)
					end
					part(wall,frame,'DoorTrim',{e.Thickness+.035,.055,B.DoorWidth},{0,B.DoorHeight+.0275,-(start+finish)*.5},trim,false)
					local open=frame*C.new(0,0,-(start+.052)*S)*C.Angles(0,math.rad(90),0)
					local leaf=B.DoorWidth-.12
					part(wall,open,'OpenDoor',{.045,B.DoorHeight-.075,leaf},{0,(B.DoorHeight-.035)*.5,-leaf*.5},{130,105,79},false)
					part(wall,open,'DoorHandle',{.09,.033,.075},{.025,1.02,-leaf+.12},{179,176,160},false)
				end
			elseif e.Kind=='Block' then
				local frame=base*C.new(e.X*S,y*S,e.Z*S)*C.Angles(0,math.rad(e.Rotation),0)
				local block=part(root,frame,'PlanBlock_'..e.Id,{e.Width,h,e.Depth},{0,h*.5,0})
				block:SetAttribute('PlanId',e.Id);block:SetAttribute('Floor',e.Floor)
			elseif e.Kind=='Stairs' then
				local continued=false
				for _,next in plan.Items do
					if next.Kind=='Stairs' and next.Floor==e.Floor+1 and next.X==e.X and next.Z==e.Z and next.Rotation==e.Rotation then continued=true;break end
				end
				stair(root,p,e,base,continued)
			elseif e.Kind=='Elevator' then elevator(root,p,e,base) end
		end
		return root
	end
	return F
end
