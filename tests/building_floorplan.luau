local r,fs,json=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local P=require('../src/BuildingParameters')
local B=require('../src/BuildingPlan')({Decode=function(s) return json.decode('json',s) end,Encode=function(v) return json.encode('json',v) end})
local Interior=require('../src/BuildingInteriorFactory')(r,B);local F=require('../src/BuildingFactory')(r,P,nil,B,Interior)
local C,V=r.CFrame,r.Vector3;local S=1/.28
local p=P.normalize({Floors=3,Width=16,Depth=12,GroundHeight=3.45,Details=false})
local plan={Version=1,Items={{Id=1,Kind='Wall',Floor=1,X=0,Z=-4.5,X2=0,Z2=2,Thickness=.16},
	{Id=2,Kind='Stairs',Floor=1,X=-4.5,Z=1,Rotation=0},{Id=3,Kind='Stairs',Floor=2,X=-4.5,Z=1,Rotation=0},
	{Id=4,Kind='Elevator',X=4.5,Z=2,Rotation=90},{Id=5,Kind='Block',Floor=2,X=2,Z=-1,Width=1,Depth=.5,Rotation=90}}}
p.PlanJSON=B.encode(plan,p);assert(#B.decode(p.PlanJSON,p).Items==5)
local base=C.new(81,4,-18)*C.Angles(0,.73,0);local b=F.create(p,base)
local custom=r.Instance.new('Part');custom.Name='UserProp';custom.Parent=b
assert(not b.Geometry.Floor_1:FindFirstChild('LobbyPartition'))
assert(not b.Geometry.Floor_2:FindFirstChild('FloorSlab'),'Upper slab did not cut stair/lift holes')
local wall=b.Geometry.FloorPlanInterior.PlanWall_1
assert((base:ToObjectSpace(wall.CFrame).Position-V.new(0,3.45*.5,-1.25)*S).Magnitude<.001)
assert(math.abs(wall.Size.Z-6.5*S)<.001 and wall.CanCollide)
local areaChecks=0
for floor=1,p.Floors do
	local holes=B.holes(plan,floor);local tiles=B.tiles(p.Width,p.Depth,holes)
	local area=0;for _,t in tiles do area+=(t.X1-t.X0)*(t.Z1-t.Z0) end
	local expected=p.Width*p.Depth;for _,h in holes do expected-=(h.X1-h.X0)*(h.Z1-h.Z0) end
	assert(math.abs(area-expected)<1e-7,'Slab subtraction changed usable floor area')
	for _,hole in holes do
		for _,part in b.Geometry['Floor_'..floor]:GetChildren() do if part:IsA('BasePart') and part.CanCollide then
			local frame=base:ToObjectSpace(part.CFrame);local half=part.Size*.5/S;local center=frame.Position/S
			local overlapX=math.min(center.X+half.X,hole.X1)-math.max(center.X-half.X,hole.X0)
			local overlapZ=math.min(center.Z+half.Z,hole.Z1)-math.max(center.Z-half.Z,hole.Z0)
			-- Facade is outside each interior opening; no hidden whole-floor bands.
			if part.Name=='FloorSlabTile' or part.Name=='FloorBand' then assert(overlapX<.0001 or overlapZ<.0001,'Floor blocks stair/lift opening') end
		end end
		areaChecks+=1
	end
end
-- Every riser is climbable and both flights land exactly on the next floor.
for _,e in plan.Items do if e.Kind=='Stairs' then
	local stair=b.Geometry.FloorPlanInterior['Stairs_'..e.Id];local h=B.height(p,e.Floor)
	local frame=base*C.new(e.X*S,B.level(p,e.Floor)*S,e.Z*S)*C.Angles(0,math.rad(e.Rotation),0)
	local lower,upper={},{}
	for _,t in stair:GetChildren() do if t.Name=='LowerTread' then table.insert(lower,t) elseif t.Name=='UpperTread' then table.insert(upper,t) end end
	table.sort(lower,function(a,c) return a.CFrame.Y<c.CFrame.Y end);table.sort(upper,function(a,c) return a.CFrame.Y<c.CFrame.Y end)
	assert(#lower==#upper and #lower>=8)
	local previous=0
	for _,t in lower do local top=(frame:ToObjectSpace(t.CFrame).Y+t.Size.Y*.5)/S;assert(top-previous<=.18001 and top>previous);previous=top end
	assert(math.abs(previous-h*.5)<.0001)
	for _,t in upper do local top=(frame:ToObjectSpace(t.CFrame).Y+t.Size.Y*.5)/S;assert(top-previous<=.18001 and top>previous);previous=top end
	assert(math.abs(previous-h)<.0001)
end end
local elevator=b.Geometry.FloorPlanInterior.Elevator_4
assert(#elevator.Stops:GetChildren()==3 and #elevator.Landings:GetChildren()==3)
assert(elevator.Cab:FindFirstChild('CabFloor') and elevator.Cab.ControlPanel.SelectFloor:IsA('ProximityPrompt'))
for _,rotation in {0,90,180,270} do
	local c=table.clone(p);local small={Version=1,Items={{Id=1,Kind='Stairs',Floor=1,X=-3,Z=0,Rotation=rotation}}}
	c.PlanJSON=B.encode(small,c);assert(F.create(c,base).Geometry.FloorPlanInterior.Stairs_1)
end
-- The pivot transform feeds actual 3D geometry and relocates slab openings.
for _,kind in {'Stairs','Elevator'} do
	local c=table.clone(p);local original={Id=1,Kind=kind,Floor=1,X=-3,Z=0,Rotation=0}
	local moved=B.transform(original,6,0,90);local edited={Version=1,Items={moved}}
	c.PlanJSON=B.encode(edited,c);local model=F.create(c,base)
	local interior=model.Geometry.FloorPlanInterior[kind..'_1'];assert(interior)
	local hole=B.holes(edited,2)[1];local coveringOld=false
	for _,part in model.Geometry.Floor_2:GetChildren() do if part.Name=='FloorSlabTile' then
		local pos=base:ToObjectSpace(part.CFrame).Position/S;local half=part.Size*.5/S
		if -3>pos.X-half.X and -3<pos.X+half.X and 0>pos.Z-half.Z and 0<pos.Z+half.Z then coveringOld=true end
		assert(math.min(pos.X+half.X,hole.X1)-math.max(pos.X-half.X,hole.X0)<.0001 or math.min(pos.Z+half.Z,hole.Z1)-math.max(pos.Z-half.Z,hole.Z0)<.0001)
	end end
	assert(coveringOld,'Moving a core left its old opening behind')
end
local rotatedWall=B.transform({Id=1,Kind='Wall',Floor=1,X=-2,Z=0,X2=2,Z2=0,Thickness=.16},1,1,30)
local c=table.clone(p);c.PlanJSON=B.encode({Items={rotatedWall}},c)
local actual=F.create(c,base).Geometry.FloorPlanInterior.PlanWall_1
local localFrame=base:ToObjectSpace(actual.CFrame)
assert((localFrame.Position-V.new(1,c.GroundHeight*.5,1)*S).Magnitude<.001)
assert(math.abs(actual.Size.Z-4*S)<.001)
local expected=V.new(rotatedWall.X2-rotatedWall.X,0,rotatedWall.Z2-rotatedWall.Z).Unit
assert(math.abs(localFrame.LookVector:Dot(expected))>.9999)
rotatedWall.DoorAt=.55;c.PlanJSON=B.encode({Items={rotatedWall}},c)
local framed=F.create(c,base).Geometry.FloorPlanInterior.PlanWall_1
assert(framed.OpenDoor.CanCollide==false and framed.DoorHeader.CanCollide)
local passage=base:PointToWorldSpace(V.new(rotatedWall.X+(rotatedWall.X2-rotatedWall.X)*.55,1.9,rotatedWall.Z+(rotatedWall.Z2-rotatedWall.Z)*.55)*S)
for _,part in framed:GetChildren() do if part.CanCollide then
	local pos=part.CFrame:PointToObjectSpace(passage);local half=part.Size*.5
	assert(math.abs(pos.X)>half.X or math.abs(pos.Y)>half.Y or math.abs(pos.Z)>half.Z,'Doorway has an invisible blocker')
end end
local tooShort=table.clone(rotatedWall);tooShort.X2,tooShort.Z2=tooShort.X+.5,tooShort.Z
assert(not pcall(B.encode,{Items={tooShort}},c))
local saved=r.deserializeModel(r.serializeModel({b},true))[1]
assert(P.read(saved).PlanJSON==p.PlanJSON and #B.decode(P.read(saved).PlanJSON,P.read(saved)).Items==5)
local before=r.serializeModel({b},true)
for _,bad in {
	{Version=1,Items={{Id=1,Kind='Stairs',Floor=3,X=0,Z=0,Rotation=0}}},
	{Version=1,Items={{Id=1,Kind='Elevator',X=100,Z=0,Rotation=0}}},
	{Version=1,Items={{Id=1,Kind='Wall',Floor=1,X=0,Z=0,X2=0/0,Z2=1}}},
	{Version=1,Items={{Id=1,Kind='Elevator',X=0,Z=0,Rotation=0},{Id=2,Kind='Wall',Floor=2,X=0,Z=-1,X2=0,Z2=1}}},
} do assert(not pcall(B.normalize,bad,p)) end
local bad=table.clone(p);bad.Width=6;assert(not pcall(F.rebuild,b,bad));assert(r.serializeModel({b},true)==before)
local reduced=table.clone(p);reduced.Floors=2;assert(not pcall(F.rebuild,b,reduced));assert(custom.Parent==b)
-- Deleting stairs/lifts closes their holes; an explicit empty plan stays empty.
local empty=table.clone(p);empty.PlanJSON=B.encode({Items={}},empty);F.rebuild(b,empty)
assert(b.Geometry.Floor_2:FindFirstChild('FloorSlab') and not b.Geometry.Floor_2:FindFirstChild('LobbyPartition'))
local out=require('@lune/process').env.BORA_VILLA_WORK
if out then fs.writeFile(out..'/building-floorplan-validation.json',json.encode('json',{FloorOpeningsChecked=areaChecks,WalkableRisers=true,FourRotations=true,PlanSaveReload=true,InvalidEditAtomic=true,UserAdditionsPreserved=true,DeleteClosesHoles=true,StudioPlaytestPerformed=false},true)) end
print('PASS: floor-plan walls/blocks, stair/lift openings, climbable risers, exact floor arrivals, rotation, save/reload, rejected edits and deletion.')
