local r,fs,json=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local P=require('../src/BuildingParameters');local B=require('../src/BuildingPlan')({Decode=function(s) return json.decode('json',s) end,Encode=function(v) return json.encode('json',v) end})
local F=require('../src/BuildingFactory')(r,P,nil,B,require('../src/BuildingInteriorFactory')(r,B))
local Motion=require('../src/BuildingElevatorMotion');local Actor=require('../src/BuildingElevatorActor')(r,Motion)
local C,V=r.CFrame,r.Vector3;local S=1/.28
local p=P.normalize({Floors=3,Width=12,Depth=10,Details=false});p.PlanJSON=B.encode({Items={{Id=1,Kind='Elevator',X=0,Z=0,Rotation=90}}},p)
local base=C.new(12,3,-8)*C.Angles(0,.32,0);local building=F.create(p,base);local lift=building.Geometry.FloorPlanInterior.Elevator_1
local characterModel=r.Instance.new('Model');characterModel.Parent=r.Instance.new('Folder');local humanoid={Health=100}
local root=r.Instance.new('Part');root.Name,root.Parent,root.Anchored='HumanoidRootPart',characterModel,false;root.CFrame=lift.ShaftOrigin.CFrame*C.new(0,1*S,0)
local character={FindFirstChild=function(_,name) return if name=='HumanoidRootPart' then root else nil end,FindFirstChildOfClass=function() return humanoid end}
local actor=Actor.new(lift,function() return {character} end)
local initial=root.CFrame;assert(actor:inside(character))
assert(Motion.request(actor.State,3));assert(not Motion.request(actor.State,999));assert(not Motion.request(actor.State,1.3))
local moving=false;local elapsed=0
for _=1,1200 do
	actor:step(1/60);elapsed+=1/60
	if actor.State.Phase=='Moving' then
		moving=true;assert(root.Anchored and actor.State.Door==0,'Lift moved without closing doors / carrying rider')
		for _,landing in actor.LandingDoors do
			assert((landing.Part.CFrame.Position-(actor.Base*landing.Frame).Position).Magnitude<.001,'Unoccupied floor door open in motion')
		end
	end
	if moving and actor.State.Phase=='Idle' then break end
end
assert(actor.State.Floor==3 and actor.State.Phase=='Idle' and not root.Anchored)
local delta=actor.Base:PointToObjectSpace(root.CFrame.Position)-actor.Base:PointToObjectSpace(initial.Position)
assert(math.abs(delta.Y-(p.GroundHeight+p.FloorHeight)*S)<.001 and math.abs(delta.X)<.001 and math.abs(delta.Z)<.001)
assert(Motion.request(actor.State,1));for _=1,1200 do actor:step(1/60);if actor.State.Phase=='Moving' then break end end
assert(root.Anchored);actor:destroy();assert(not root.Anchored,'Destroyed lift left rider anchored')
local fresh=F.create(p,base).Geometry.FloorPlanInterior.Elevator_1
local held=Actor.new(fresh,function() return {character} end)
root.CFrame=held.Base*C.new(0,1*S,-1.3*S);Motion.request(held.State,2)
for _=1,180 do held:step(1/60) end
assert(held.State.Phase=='Closing' and held.State.Door==1 and not root.Anchored,'Doorway occupant was trapped / lift departed')
root.CFrame=held.Base*C.new(0,1*S,0)
for _=1,120 do held:step(1/60) end
assert(held.State.Phase=='Moving' and root.Anchored);held:destroy();assert(not root.Anchored)
-- Initially anchored or outside characters must not be taken over.
root.CFrame=lift.ShaftOrigin.CFrame*C.new(9*S,1*S,0);assert(not actor:inside(character))
for _,dt in {1/30,1/60,1/120} do
	local state=Motion.new({0,3.45,6.5});assert(Motion.request(state,3));assert(Motion.request(state,2));local seen={}
	for _=1,math.ceil(30/dt) do Motion.step(state,dt);if state.Phase=='Idle' then seen[state.Floor]=true end end
	assert(seen[3] and seen[2] and state.Floor==2 and state.Door==1)
end
fs.writeFile('dist/building-elevator-validation.json',json.encode('json',{DoorsCloseBeforeTravel=true,QueueAndFrameRates=true,PassengersReachSelectedFloor=true,PassengersReleasedOnRemoval=true,InvalidStopsRejected=true,StudioPlaytestPerformed=false},true))
print('PASS: actual elevator actor, doors, passenger height, queued stops, removal cleanup, invalid calls and 30/60/120Hz motion.')
