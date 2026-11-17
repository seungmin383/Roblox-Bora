local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local Path=require('../src/RoadPath')(r.Vector3)
local Traffic=require('../src/RoadTraffic')(r,Path,nil,require('../src/TrafficAssetLayout'))
local Roads=require('../src/RoadNetworkFactory')(r,Path,Traffic)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J,Traffic)
local Timing=require('../src/TrafficTiming')
local V=r.Vector3.new
local function scene()
	local folder=r.Instance.new('Folder')
	local a=Roads.create({V(-180,0,0),V(180,0,0)},{Curve=0},'A');a.Name='A';a.Parent=folder
	local b=Roads.create({V(0,0,-180),V(0,0,180)},{Curve=0},'B');b.Name='B';b.Parent=folder
	return folder,a,b
end
local f,a,b=scene();N.apply(f)
local junction=f.Junctions:GetChildren()[1]
assert(#junction.Signals:GetChildren()==4)
local crossArms,stopArms={},{}
for _,group in junction.Markings:GetChildren() do
	local arm=group:GetAttribute('Arm')
	if group.Name=='Crosswalk' then crossArms[arm]=true else assert(group.Name=='StopLine');stopArms[arm]=true end
	for _,part in group:GetChildren() do assert(part.Anchored and not part.CanCollide and not part.CanQuery) end
end
for i=1,4 do assert(crossArms[i] and stopArms[i],'Missing approach markings') end
local da,db=Path.sample(Roads.points(a),Roads.config(a)),Path.sample(Roads.points(b),Roads.config(b))
local plan=J.planApproaches({{Data=da,At=.5},{Data=db,At=.5}})
local traffic=Traffic.plan(plan,Traffic.Defaults)
assert(#traffic.Signals==4 and #traffic.Cuts==4)
for _,mark in traffic.Markings do if mark.Kind=='StopLine' then
	local center=V(0,0,0);for _,corner in mark.Corners do center+=corner*.25 end
	local arm=plan.Arms[mark.Arm];local q=Path.project(arm.Data,center)
	assert((center-q):Dot(V(-arm.Direction.Z,0,arm.Direction.X))<0,'Stop line is on the departing side')
end end
for _,signal in traffic.Signals do
	local arm=plan.Arms[signal.Arm];local q=Path.project(arm.Data,signal.Position)
	assert((signal.Position-q):Dot(signal.Side)<0,'Pole must be on the approaching drivers right')
end
for _,road in {a,b} do for _,mark in road.Geometry.Markings:GetChildren() do
	local _,distance=Path.project(if road==a then da else db,mark.CFrame.Position)
	for _,cut in traffic.Cuts do
		if cut.Approach==(if road==a then 1 else 2) then assert(distance<=cut.Range[1]+.001 or distance>=cut.Range[2]-.001,'Lane line overlaps crossing/stop line') end
	end
end end
local phases={}
for _,signal in junction.Signals:GetChildren() do
	local phase=signal:GetAttribute('Phase');phases[phase]=(phases[phase] or 0)+1
	assert(signal.TripoHead:FindFirstChildOfClass('SpecialMesh').MeshId=='rbxasset://BoraRoadKit/TrafficSignal.mesh')
	assert(signal.Pole.CanCollide and not signal.TripoHead.CanCollide)
	for _,name in {'Red','Amber','Green'} do assert(signal[name]:GetAttribute('SignalLamp')==name) end
	assert((signal.Red.CFrame.Position-signal.Green.CFrame.Position):Dot(signal.TripoHead.CFrame.RightVector)>0,'Red must be on the drivers left')
end
assert(phases[1]==2 and phases[2]==2)
for t=0,330,.1 do
	local one,two=Timing.state(t,1,12,3,1.5),Timing.state(t,2,12,3,1.5)
	assert(not (one~='Red' and two~='Red'),'Conflicting phases are active')
end
assert(Timing.state(0,1,12,3,1.5)=='Green' and Timing.state(12,1,12,3,1.5)=='Amber')
assert(Timing.state(15,1,12,3,1.5)=='Red' and Timing.state(16.5,2,12,3,1.5)=='Green')
-- Toggle and spacing changes persist, including false booleans.
local settings=table.clone(Traffic.Defaults);settings.Crosswalks=false;settings.Signals=false;settings.StopGap=2
N.apply(f,nil,nil,nil,nil,settings)
junction=f.Junctions:GetChildren()[1]
assert(#junction.Signals:GetChildren()==0 and #junction.Markings:GetChildren()==4)
assert(f:GetAttribute('Crosswalks')==false and f:GetAttribute('Signals')==false)
for _,mark in junction.Markings:GetChildren() do assert(mark.Name=='StopLine') end
settings.StopLines=false;N.apply(f,nil,nil,nil,nil,settings)
assert(#f.Junctions:GetChildren()[1].Markings:GetChildren()==0)
N.apply(f,nil,nil,nil,nil,Traffic.Defaults)
settings=table.clone(Traffic.Defaults);settings.CrosswalkWidth=4;settings.CrosswalkOffset=1.5;settings.GreenSeconds=20
N.apply(f,nil,nil,nil,nil,settings)
local saved=r.deserializeModel(r.serializeModel({f},true))[1]
assert(Traffic.config(saved).CrosswalkWidth==4 and Traffic.config(saved).GreenSeconds==20)
N.apply(saved);assert(#saved.Junctions:GetChildren()[1].Signals:GetChildren()==4)
-- Host/width movement carries markings and signal poles with the junction.
N.edit(f,a,{V(-180,0,30),V(180,0,30)},{Curve=0,Width=10,Sidewalk=2},false)
local patch=f.Junctions:GetChildren()[1]
assert(math.abs(patch:GetAttribute('Center').Z-30)<.001)
-- Invalid settings/short approaches leave all geometry and settings unchanged.
local oldA,oldB,oldPatch=a.Geometry,b.Geometry,f.Junctions
assert(not pcall(function() N.apply(f,nil,nil,nil,nil,{CrosswalkWidth=99}) end))
assert(not pcall(function() N.edit(f,b,{V(0,0,25),V(0,0,180)},Roads.config(b),false) end))
assert(a.Geometry==oldA and b.Geometry==oldB and f.Junctions==oldPatch)
assert(f:GetAttribute('CrosswalkWidth')==4)
-- A short link between two valid junctions omits crowded paint, not geometry.
local compact=r.Instance.new('Folder')
local trunk=Roads.create({V(-180,0,0),V(180,0,0)},{Curve=0},'Trunk');trunk.Parent=compact
for _,x in {-35,35} do local branch=Roads.create({V(x,0,-140),V(x,0,140)},{Curve=0},tostring(x));branch.Parent=compact end
local _,limited=N.apply(compact);assert(limited.Cross==2 and limited.Limited==2)
local restoreSettings=table.clone(Traffic.Defaults);restoreSettings.Crosswalks=false;restoreSettings.StopGap=.5
local _,fitted=N.apply(compact,nil,nil,nil,nil,restoreSettings);assert(fitted.Limited==0)
-- Sloped and curved approach stripes conform to sampled asphalt.
local slope=Path.sample({V(-180,-10,0),V(0,0,10),V(180,10,0)},{Curve=50})
local through=Path.sample({V(0,0,-180),V(0,0,180)},{Curve=0})
local slopedPlan=J.planApproaches({{Data=slope,At=.5},{Data=through,At=190/360}})
local sloped=Traffic.plan(slopedPlan,Traffic.Defaults)
for _,mark in sloped.Markings do
	local arm=slopedPlan.Arms[mark.Arm]
	for _,p in mark.Corners do
		local q=Path.project(arm.Data,p)
		assert(math.abs(p.Y-q.Y-arm.Data.Config.Lift*Path.StudsPerMeter-.045)<.06,'Marking floats above slope')
	end
end
-- Export only models/JSON for visual inspection; never another Place.
fs.writeFile('dist/TrafficJunction.rbxmx',r.serializeModel({f},true))
local marks={};for _,mark in traffic.Markings do
	local corners={};for _,p in mark.Corners do table.insert(corners,{p.X,p.Y,p.Z}) end
	table.insert(marks,{Kind=mark.Kind,Corners=corners})
end
local perimeter={};for _,p in plan.Perimeter do table.insert(perimeter,{p.X,p.Y,p.Z}) end
fs.writeFile('dist/traffic-layout.json',serde.encode('json',{Markings=marks,Perimeter=perimeter},true))
for _,name in {'RoadTraffic','TrafficTiming','RoadTrafficRuntime.server','RoadEditorPlugin.server'} do require('@lune/luau').compile(fs.readFile('src/'..name..'.luau')) end
print('PASS: four crosswalks/stop lines/Tripo heads, no line overlap, noncolliding paint, toggles/spacing persistence, movement/width, slope conformance, atomic errors, alternating server phases/amber/all-red.')
