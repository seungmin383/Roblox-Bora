-- Stage only the villa's replacement geometry, never a Place.
return function(out)
	local r,fs,json=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
	local C,V,I=r.CFrame,r.Vector3,r.Instance;local S=1/.28
	local P=require('../src/BuildingParameters')
	local B=require('../src/BuildingPlan')({Decode=function(s) return json.decode('json',s) end,Encode=function(v) return json.encode('json',v) end})
	local F=require('../src/BuildingFactory')(r,P,nil,B,require('../src/BuildingInteriorFactory')(r,B))
	local place=r.deserializePlace(fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*',''))
	local villa=place:GetService('Workspace').BoraNeighborhood_01.Buildings.BoraVilla
	local g=villa.Geometry;local base=villa.BuildingOrigin.CFrame;local p=P.read(villa)
	assert(p.Floors==3 and p.Width==10.8 and p.Depth==9.4 and p.PlanJSON=='','Villa recipe differs from the original; preserve newer edits.')
	assert(g.UpperMasonry and g.GroundCeiling and not g:FindFirstChild('FloorPlanInterior'))
	local items={
		{Id=1,Kind='Stairs',Floor=1,X=-3.25,Z=1.25,Rotation=0},
		{Id=2,Kind='Stairs',Floor=2,X=-3.25,Z=1.25,Rotation=0},
		{Id=3,Kind='Elevator',Floor=1,X=2.75,Z=1.25,Rotation=0},
		{Id=4,Kind='Wall',Floor=2,X=-5,Z=-2.75,X2=5,Z2=-2.75,Thickness=.16,DoorAt=.65},
		{Id=5,Kind='Wall',Floor=3,X=-5,Z=-2.75,X2=5,Z2=-2.75,Thickness=.16,DoorAt=.65},
	}
	p.PlanJSON=B.encode({Items=items},p)
	local patch=I.new('Model');patch.Name='BoraVilla'
	for key,value in villa:GetAttributes() do patch:SetAttribute(key,value) end
	P.write(patch,p)
	local geometry=I.new('Model');geometry.Name='Geometry';geometry.Parent=patch
	for key,value in g:GetAttributes() do geometry:SetAttribute(key,value) end
	geometry:SetAttribute('BoraRetainedShell',true)
	local jambX=0;local jambs=0
	for _,part in g:GetChildren() do if part.Name=='DoorJamb' then jambX+=base:ToObjectSpace(part.CFrame).X/S;jambs+=1 end end
	assert(jambs==2);local entryX=jambX/jambs;geometry:SetAttribute('PlanEntryX',entryX)
	local shell=I.new('Model');shell.Name='RetainedExteriorWalls';shell.Parent=geometry
	local function perimeter(original,thickness,prefix)
		assert(#original:GetChildren()==0,'Original solid has attached objects')
		local size=original.Size/S;local w,h,d=size.X,size.Y,size.Z
		local function add(suffix,x,z,width,depth)
			local wall=original:Clone();wall.Name=prefix..suffix;wall.Size=V.new(width,h,depth)*S
			wall.CFrame=original.CFrame*C.new(x*S,0,z*S);wall.Parent=shell
		end
		for _,side in {-1,1} do
			add(if side<0 then 'Front' else 'Rear',0,side*(d-thickness)*.5,w,thickness)
			add(if side<0 then 'Left' else 'Right',side*(w-thickness)*.5,0,thickness,d-thickness*2)
		end
	end
	perimeter(g.UpperMasonry,.20,'UpperWall')
	local bands=0
	for _,part in g:GetChildren() do if part.Name=='FloorBand' then bands+=1;perimeter(part,.19,'FloorBand'..bands) end end
	assert(bands==2)
	F.retainedInterior(geometry,p,base)
	local fixtures=I.new('Model');fixtures.Name='VillaHallLighting';fixtures.Parent=geometry
	for floor=1,p.Floors do
		for _,x in {-2.75,2.75} do
			local y=B.level(p,floor)+B.height(p,floor)-.24
			local lamp=I.new('Part');lamp.Name='HallCeilingLight';lamp.Size=V.new(.52,.065,.24)*S
			lamp.CFrame=base*C.new(x*S,y*S,-1.88*S)
			lamp.Anchored,lamp.CanCollide,lamp.CanQuery,lamp.CanTouch=true,false,false,false
			lamp.Material,lamp.Color,lamp.Parent=r.Enum.Material.Neon,r.Color3.fromRGB(250,241,219),fixtures
			local light=I.new('SurfaceLight');light.Face=r.Enum.NormalId.Bottom;light.Range,light.Angle,light.Brightness=20,160,1.6
			light.Color,light.Parent=lamp.Color,lamp
		end
	end
	-- Verify the real slabs, landings and path against the original colliders.
	local pboxes={}
	for _,part in g:GetDescendants() do if part:IsA('BasePart') and part.CanCollide
		and part.Name~='UpperMasonry' and part.Name~='GroundCeiling' and part.Name~='FloorBand' then
		table.insert(pboxes,{part=part,frame=part.CFrame:Inverse()*base,half=part.Size*.5/S})
	end end
	for _,part in geometry:GetDescendants() do if part:IsA('BasePart') and part.CanCollide then
		table.insert(pboxes,{part=part,frame=part.CFrame:Inverse()*base,half=part.Size*.5/S})
	end end
	local function rayClear(x,y,z,radius,height,step)
		for _,box in pboxes do
			for _,dx in {-radius,0,radius} do for _,dz in {-radius,0,radius} do
				local low=box.frame:PointToWorldSpace(V.new(x+dx,y+(step or .025),z+dz)*S)/S
				local high=box.frame:PointToWorldSpace(V.new(x+dx,y+height,z+dz)*S)/S
				local half=box.half
				assert(math.abs(low.X)>=half.X-.001 or math.abs(low.Z)>=half.Z-.001
					or math.max(low.Y,high.Y)<=-half.Y+.001 or math.min(low.Y,high.Y)>=half.Y-.001,
					string.format('Route obstructed by %s at %.2f, %.2f, %.2f',box.part.Name,x,y,z))
			end end
		end
	end
	local checked=0
	local function path(y,points)
		for i=2,#points do
			local a,b=points[i-1],points[i];local n=math.max(1,math.ceil(math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)/.08))
			for j=0,n do local t=j/n;rayClear(a[1]+(b[1]-a[1])*t,y,a[2]+(b[2]-a[2])*t,.26,1.95);checked+=1 end
		end
	end
	path(0,{{entryX,-5.2},{entryX,-1.8},{-3.98,-1.8},{-3.98,-1.45}})
	for floor=1,3 do
		local y=B.level(p,floor)
		path(y,{{-2.52,-1.45},{-2.52,-1.84},{2.75,-1.84},{2.75,-.55}})
		if floor>1 then path(y,{{1.5,-1.84},{1.5,-3.45}}) end
	end
	local interior=geometry.FloorPlanInterior
	assert(not interior.Stairs_1:FindFirstChild('UpperFrontGuard') and interior.Stairs_2:FindFirstChild('UpperFrontGuard'))
	assert(interior.Elevator_3.Cab.PrimaryPart==interior.Elevator_3.Cab.CabRoot and #interior.Elevator_3.Stops:GetChildren()==3)
	local function close(a,b) assert(math.abs(a-b)<.0001,tostring(a)..' ~= '..tostring(b)) end
	for _,stair in {interior.Stairs_1,interior.Stairs_2} do
		local floor=stair:GetAttribute('FromFloor');local h=B.height(p,floor);local y=B.level(p,floor)
		local maximum=0
		for _,tread in stair:GetChildren() do if tread.Name=='UpperTread' then
			maximum=math.max(maximum,base:ToObjectSpace(tread.CFrame).Y/S+tread.Size.Y*.5/S)
		end
			if tread.Name=='LowerTread' or tread.Name=='UpperTread' or tread.Name=='MidLanding' then
				local at=base:ToObjectSpace(tread.CFrame).Position/S
				rayClear(at.X,at.Y+tread.Size.Y*.5/S,at.Z,.26,1.95,.20);checked+=1
			end
		end
		close(maximum,y+h)
		assert(3.7/math.ceil(h/.36)>.3 and h/(2*math.ceil(h/.36))<=.18)
	end
	local motion=require('../src/BuildingElevatorMotion')
	local elevator=interior.Elevator_3:Clone();local actor=require('../src/BuildingElevatorActor')(r,motion).new(elevator,function() return {} end)
	for _,floor in {2,3,1} do
		assert(motion.request(actor.State,floor))
		for _=1,1200 do actor:step(1/60);if actor.State.Phase=='Idle' and actor.State.Floor==floor then break end end
		assert(actor.State.Floor==floor and actor.State.Phase=='Idle')
		close(base:ToObjectSpace(elevator.Cab.CabRoot.CFrame).Y/S,B.level(p,floor))
	end
	actor:destroy()
	-- A plan-only rebuild should keep the retained facade while changing its interior.
	local trial=villa:Clone();trial.Geometry:Destroy();geometry:Clone().Parent=trial;P.write(trial,p)
	local updated=table.clone(p);local revised=B.decode(p.PlanJSON,p)
	revised.Items[5].DoorAt=.55;updated.PlanJSON=B.encode(revised,p)
	local previous=F.rebuild(trial,updated)
	assert(previous.Parent==nil and trial.Geometry:FindFirstChild('RetainedExteriorWalls'))
	assert(trial.Geometry:GetAttribute('PlanEntryX')==entryX and P.read(trial).PlanJSON==updated.PlanJSON)
	fs.writeFile(out..'/villa-patch.rbxmx',r.serializeModel({patch},true))
	fs.writeFile(out..'/villa-plan-validation.json',json.encode('json',{Config=p,Plan=items,EntryX=entryX,RoutePoints=checked,StudioPlaytestPerformed=false},true))
	print('Staged 3 floors, 2 stair runs, 3 elevator stops and 2 doorways; corridor clearance sampled at '..checked..' points.')
end
