local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local Path=require('../src/RoadPath')(r.Vector3)
local Traffic=require('../src/RoadTraffic')(r,Path,nil,require('../src/TrafficAssetLayout'))
local Roads=require('../src/RoadNetworkFactory')(r,Path,Traffic)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J,Traffic)
local Timing=require('../src/TrafficTiming')
local V=r.Vector3.new
local function road(folder,points,id)
	local model=Roads.create(points,{Curve=0},id);model.Name=id;model.Parent=folder;return model
end
local f=r.Instance.new('Folder')
local a=road(f,{V(-180,0,0),V(180,0,0)},'A')
local b=road(f,{V(0,0,-180),V(0,0,180)},'B')
N.apply(f)
local function check(junction,expected)
	local signals=junction.PedestrianSignals:GetChildren();assert(#signals==expected)
	local arms={}
	for _,signal in signals do
		local index=signal:GetAttribute('CrosswalkArm')
		arms[index]=arms[index] or {};table.insert(arms[index],signal)
		assert(signal:GetAttribute('SignalKind')=='Pedestrian' and signal:GetAttribute('AssetSource')=='Tripo Studio')
		assert(signal.TripoPedestrianHead:FindFirstChildOfClass('SpecialMesh').MeshId=='rbxasset://BoraRoadKit/PedestrianSignal.mesh')
		assert(signal.Pole.CanCollide and not signal.TripoPedestrianHead.CanCollide)
		for _,piece in signal.StopIcon:GetChildren() do assert(piece.Transparency==0 and not piece.CanCollide and piece.Material==r.Enum.Material.Neon) end
		for _,piece in signal.WalkIcon:GetChildren() do assert(piece.Transparency==1 and not piece.CanQuery) end
	end
	for _,pair in arms do
		assert(#pair==2,'A crossing must have two opposing heads')
		local h1,h2=pair[1].TripoPedestrianHead,pair[2].TripoPedestrianHead
		assert(h1.CFrame.LookVector:Dot(h2.CFrame.LookVector)<-.999)
		local delta=h2.CFrame.Position-h1.CFrame.Position
		assert(h1.CFrame.LookVector:Dot(delta.Unit)>.99,'Head does not face the opposite curb')
	end
end
check(f.Junctions:GetChildren()[1],8)
-- Legacy settings acquire new defaults; toggles/seconds survive save/reload.
assert(Traffic.config(f).PedestrianSignals and Traffic.config(f).WalkSeconds==10)
local settings=table.clone(Traffic.Defaults);settings.PedestrianSignals=false
N.apply(f,nil,nil,nil,nil,settings);check(f.Junctions:GetChildren()[1],0)
assert(#f.Junctions:GetChildren()[1].Signals:GetChildren()==4)
settings.PedestrianSignals=true;settings.WalkSeconds=18;settings.FlashSeconds=6
N.apply(f,nil,nil,nil,nil,settings)
local saved=r.deserializeModel(r.serializeModel({f},true))[1]
N.apply(saved);check(saved.Junctions:GetChildren()[1],8)
assert(Traffic.config(saved).WalkSeconds==18 and Traffic.config(saved).FlashSeconds==6)
settings.Crosswalks=false;N.apply(f,nil,nil,nil,nil,settings);check(f.Junctions:GetChildren()[1],0)
N.apply(f,nil,nil,nil,nil,Traffic.Defaults)
-- Moving/widening a road regenerates the two curb positions.
local before=f.Junctions:GetChildren()[1].PedestrianSignals:GetChildren()[1].Pole.CFrame.Position
N.edit(f,a,{V(-180,0,30),V(180,0,30)},{Curve=0,Width=10,Sidewalk=2},false)
check(f.Junctions:GetChildren()[1],8)
local after=f.Junctions:GetChildren()[1].PedestrianSignals:GetChildren()[1].Pole.CFrame.Position
assert((after-before).Magnitude>10)
-- Crowded approaches without crosswalk paint must have no orphan heads.
local compact=r.Instance.new('Folder')
road(compact,{V(-180,0,0),V(180,0,0)},'Trunk')
for _,x in {-35,35} do road(compact,{V(x,0,-140),V(x,0,140)},tostring(x)) end
local _,stats=N.apply(compact);assert(stats.Limited==2)
local total=0;for _,junction in compact.Junctions:GetChildren() do total+=#junction.PedestrianSignals:GetChildren() end
assert(total==12,'Pedestrian heads remained on omitted crosswalks')
-- Every pedestrian green/flash interval holds both vehicle phases at red.
for _,green in {5,12,60} do for _,walk in {6,10,60} do for _,flash in {2,4,10} do
	local cycle=2*(green+3+1.5)+walk+flash+1.5
	for _,base in {0,1792140000} do for t=0,cycle*2,.125 do
		local time=base+t
		local state,lit=Timing.pedestrian(time,green,3,1.5,walk,flash)
		local one,two=Timing.state(time,1,green,3,1.5,walk,flash),Timing.state(time,2,green,3,1.5,walk,flash)
		assert(not(one~='Red' and two~='Red'))
		if state~='Red' or lit then assert(one=='Red' and two=='Red','Vehicle movement overlaps a pedestrian interval') end
	end end
end end end
local start=33
assert(Timing.state(start,1,12,3,1.5,10,4)=='Red')
assert(Timing.pedestrian(start,12,3,1.5,10,4)=='Walk')
local state,on=Timing.pedestrian(start+10,12,3,1.5,10,4);assert(state=='Flash' and on)
local _,off=Timing.pedestrian(start+10.5,12,3,1.5,10,4);assert(not off)
assert(Timing.pedestrian(start+14,12,3,1.5,10,4)=='Red')
assert(Timing.state(start+14,1,12,3,1.5,10,4)=='Red')
assert(Timing.state(start+15.5,1,12,3,1.5,10,4)=='Green')
assert(Timing.pedestrian(0,12,3,1.5,0,4)=='Red')
local previous=f.Junctions
assert(not pcall(function() N.apply(f,nil,nil,nil,nil,{WalkSeconds=0}) end))
assert(f.Junctions==previous)
fs.writeFile('dist/PedestrianJunction.rbxmx',r.serializeModel({f},true))
local head=f.Junctions:GetChildren()[1].PedestrianSignals:GetChildren()[1]
local centers={}
for _,name in {'StopIcon','WalkIcon'} do
	local localPoint=head.TripoPedestrianHead.CFrame:PointToObjectSpace(head[name].Head.CFrame.Position)/Path.StudsPerMeter-V(0,.105,0)
	table.insert(centers,{localPoint.X,localPoint.Y,localPoint.Z})
end
fs.writeFile('dist/pedestrian-display-calibration.json',serde.encode('json',{CentersMeters=centers},true))
for _,name in {'RoadTraffic','TrafficTiming','RoadTrafficRuntime.server','RoadEditorPlugin.server'} do require('@lune/luau').compile(fs.readFile('src/'..name..'.luau')) end
print('PASS: 8 Tripo pedestrian heads, paired directions, standing/walking glyphs, toggles/timers/reload, road edits, omitted-crosswalk cleanup, all-vehicle-red pedestrian phase, flashing/boundaries/large clocks, atomic invalid settings.')
