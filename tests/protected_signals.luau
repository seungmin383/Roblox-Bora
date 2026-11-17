local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local Path=require('../src/RoadPath')(r.Vector3)
local L=require('../src/LaneDirections')(r,Path)
local Traffic=require('../src/RoadTraffic')(r,Path,L,require('../src/TrafficAssetLayout'))
local Roads=require('../src/RoadNetworkFactory')(r,Path,Traffic)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J,Traffic,L)
local Timing=require('../src/TrafficTiming')
local V=r.Vector3.new
local function approaches(junction)
	local result={}
	for _,signal in junction.Signals:GetChildren() do
		table.insert(result,{Arm=signal:GetAttribute('Arm'),Mask=signal:GetAttribute('MovementMask')})
	end
	return result
end
local function validate(program,input)
	local duration=Timing.duration(program,5,4,3,1.5,6,2)
	local seen={}
	for _,base in {0,1792140000} do for time=0,duration*2,.125 do
		local snap=Timing.snapshot(base+time,program,5,4,3,1.5,6,2)
		local active=0
		for _,approach in input do
			local lamp=Timing.lamps(snap,approach.Arm,approach.Mask)
			assert(not(lamp.Green and lamp.Left),'Circular green and left overlap')
			if lamp.Left then assert(lamp.Red and bit32.band(approach.Mask,2)~=0);seen[approach.Arm..'Left']=true end
			if lamp.Green then assert(not lamp.Red and bit32.band(approach.Mask,1)~=0);seen[approach.Arm..'Straight']=true end
			if lamp.Green or lamp.Left or lamp.Amber then active+=1 end
			if snap.PedestrianBlocked then
				assert(lamp.Red and not lamp.Green and not lamp.Left and not lamp.Amber and not lamp.RightTurnAllowed,'Walk/flash/clearance permits a vehicle')
			end
			assert(lamp.RightTurnMustYield==(bit32.band(approach.Mask,4)~=0))
		end
		assert(active<=1,'Conflicting protected movements')
	end end
	for _,p in program do if p.Movement~='Yield' then assert(seen[p.Arm..p.Movement],'Movement was starved') end end
end
for mask=1,7 do
	local input={{Arm=1,Mask=mask},{Arm=2,Mask=7},{Arm=3,Mask=2}}
	local program=Timing.program(input);validate(program,input)
	for _,phase in program do if phase.Arm==1 then
		assert(bit32.band(mask,if phase.Movement=='Straight' then 1 else 2)~=0)
	end end
end
local onlyRight={{Arm=1,Mask=4},{Arm=2,Mask=4},{Arm=3,Mask=4}}
local yield=Timing.program(onlyRight);assert(#yield==1 and yield[1].Movement=='Yield')
validate(yield,onlyRight)
assert(Timing.lamps(Timing.snapshot(0,yield,5,4,3,1.5,6,2),1,4).RightTurnAllowed)
assert(Timing.snapshot(0,{},5,4,3,1.5,0,2).CycleSeconds==0)
assert(not pcall(Timing.program,{{Arm=1,Mask=1},{Arm=1,Mask=2}}))
-- Exact interval boundaries, including clearance after the walking icon goes dark.
local one=Timing.program({{Arm=1,Mask=3}})
for _,case in {{0,'Straight','Green'},{5,'Straight','Amber'},{8,'Straight','Clearance'},
	{9.5,'Left','Green'},{13.5,'Left','Amber'},{16.5,'Left','Clearance'}} do
	local snap=Timing.snapshot(case[1],one,5,4,3,1.5,6,2)
	assert(snap.Movement==case[2] and snap.Stage==case[3])
end
assert(Timing.snapshot(18,one,5,4,3,1.5,6,2).Pedestrian=='Walk')
assert(Timing.snapshot(24,one,5,4,3,1.5,6,2).Pedestrian=='Flash')
assert(Timing.snapshot(26,one,5,4,3,1.5,6,2).PedestrianBlocked)
assert(Timing.snapshot(27.5,one,5,4,3,1.5,6,2).Movement=='Straight')
-- The real editor path must regenerate the head after lane edits, reloads,
-- width changes and removal of left-turn permission.
local world=r.Instance.new('Folder')
local f=r.Instance.new('Folder');f.Name,f.Parent='BoraRoads',world
local a=Roads.create({V(-210,0,0),V(210,0,0)},{Curve=0,Width=21,Lanes=6},'A');a.Name,a.Parent='A',f
local b=Roads.create({V(0,0,-210),V(0,0,210)},{Curve=0,Width=14,Lanes=4},'B');b.Name,b.Parent='B',f
N.apply(f)
local function set(mask)
	local e=L.entries(f,a)[1];N.setLane(f,e.Junction,a,e.Sign,1,mask)
	return L.entries(f,a)[1]
end
local e=set(3)
local head=e.Junction.Signals:FindFirstChild('Signal_'..e.Arm)
local headName=head.Name
assert(head.Left and #head.Left:GetChildren()==3 and head.GreenHousing and head.LeftBacking)
assert(head:GetAttribute('MovementMask')==3 and head:GetAttribute('RightTurnPolicy')=='StopAndYield')
assert(not head:FindFirstChild('Right'),'No dedicated right-turn lamp')
for _,p in head.Left:GetChildren() do assert(p.Anchored and not p.CanCollide and not p.CanQuery) end
local localGreen=head.TripoHead.CFrame:PointToObjectSpace(head.Green.CFrame.Position)/Path.StudsPerMeter
assert(math.abs(localGreen.X-Traffic.AssetLayout.Vehicle.ExtensionCenter[1])<.001)
local arrowTip=head.TripoHead.CFrame:PointToObjectSpace(head.Left.Segment2.CFrame.Position)
assert(arrowTip.X>Traffic.AssetLayout.Vehicle.Centers[3][1]*Path.StudsPerMeter,'Left arrow points to drivers right')
local input=approaches(e.Junction);validate(Timing.program(input),input)
local saved=r.deserializeModel(r.serializeModel({f},true))[1]
N.apply(saved)
assert(saved.Junctions:GetChildren()[1].Signals:FindFirstChild(headName).Left)
e=set(1);assert(not e.Junction.Signals:FindFirstChild(headName):FindFirstChild('Left'),'Obsolete arrow survived a lane change')
e=set(7)
local settings=table.clone(Traffic.Defaults);settings.LeftSeconds=17
N.apply(f,nil,nil,nil,nil,settings)
assert(Traffic.config(r.deserializeModel(r.serializeModel({f},true))[1]).LeftSeconds==17)
local old=f.Junctions
assert(not pcall(N.apply,f,nil,nil,nil,nil,{LeftSeconds=0}) and f.Junctions==old)
-- Execute the actual server refresh against Lune instances and a fake clock.
local now=0
r.implementMethod('Folder','GetServerTimeNow',function() return now end)
local runtime=fs.readFile('src/RoadTrafficRuntime.server.luau'):gsub('while true do refresh%(%)%; task.wait%(%s*%.1%) end','return refresh')
assert(runtime:find('return refresh',1,true),'Runtime test did not remove infinite loop')
local chunk=compiler.load(runtime)
setfenv(chunk,setmetatable({workspace=world,script={WaitForChild=function() return 'Timing' end},
	require=function() return Timing end,Color3=r.Color3,Enum=r.Enum},{__index=getfenv()}))
local refresh=chunk()
local junction=f.Junctions:GetChildren()[1]
local program=Timing.program(approaches(junction))
local cycle=Timing.duration(program,12,17,3,1.5,10,4)
local arrowLit=false;local pedLit=false
for time=0,cycle*2,.5 do
	now=time;refresh()
	local snap=Timing.snapshot(now,program,12,17,3,1.5,10,4)
	for _,s in junction.Signals:GetChildren() do
		local lamps=Timing.lamps(snap,s:GetAttribute('Arm'),s:GetAttribute('MovementMask'))
		assert(s.Green.Material==(if lamps.Green then r.Enum.Material.Neon else r.Enum.Material.SmoothPlastic))
		if s:FindFirstChild('Left') then
			for _,p in s.Left:GetChildren() do assert(p.Material==(if lamps.Left then r.Enum.Material.Neon else r.Enum.Material.SmoothPlastic)) end
			arrowLit=arrowLit or lamps.Left
		end
		assert(s:GetAttribute('RightTurnAllowed')==lamps.RightTurnAllowed)
	end
	for _,p in junction.PedestrianSignals:GetChildren() do
		assert(p.WalkIcon.Head.Transparency==(if snap.WalkLit then 0 else 1))
	end
	pedLit=pedLit or snap.WalkLit
end
assert(arrowLit and pedLit)
-- Use a known left phase for an exported visual, without creating a Place.
for time=0,cycle,.25 do
	local snap=Timing.snapshot(time,program,12,17,3,1.5,10,4)
	if snap.Movement=='Left' and snap.Stage=='Green' then now=time;refresh();break end
end
fs.writeFile('dist/ProtectedSignalJunction.rbxmx',r.serializeModel({f},true))
print('PASS: all masks, protected phases, boundaries, right-turn yield, pedestrian clearance, head edit/reload, timer persistence, and actual runtime lamps.')
