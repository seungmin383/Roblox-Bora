local r,fs=require('@lune/roblox'),require('@lune/fs')
local Path=require('../src/RoadPath')(r.Vector3)
local Roads=require('../src/RoadNetworkFactory')(r,Path)
local Guides=require('../src/MapGuideFactory')(r)
local function near(a,b) return (a-b).Magnitude<.0002 end
local straight={r.Vector3.zero,r.Vector3.new(100,0,0)}
local road=Roads.create(straight,{Width=7,Lanes=2,Sidewalk=1.5},'stable-road')
assert(road:GetAttribute('NodeCount')==2)
assert(math.abs(road:GetAttribute('LengthMeters')-28)<.001)
local volume=0
for _,part in road.Geometry.Asphalt:GetChildren() do
	assert(part:IsA('WedgePart') and part.Anchored and part.CanCollide and not part.CanTouch)
	assert(math.abs(part.CFrame.RightVector.Y)>.999,'Flat asphalt became a vertical wall')
	volume+=part.Size.X*part.Size.Y*part.Size.Z*.5
end
assert(math.abs(volume-100*7*Path.StudsPerMeter*.6)<.05,'Road strip has missing or duplicate surface area')
assert(#road.Geometry.Sidewalks:GetChildren()>0 and #road.Geometry.Markings:GetChildren()>0)
local curved={r.Vector3.zero,r.Vector3.new(40,3,25),r.Vector3.new(100,8,30)}
local sampled=Path.sample(curved,{Curve=80})
assert(near(sampled.Samples[1].P,curved[1]) and near(sampled.Samples[#sampled.Samples].P,curved[3]))
for _,s in sampled.Samples do assert(s.Side.Magnitude>.999 and s.Side.Magnitude<1.001 and s.Miter<=2) end
Roads.rebuild(road,curved,{Width=8,Lanes=2,Sidewalk=0,Curve=80})
assert(road:GetAttribute('ObjectId')=='stable-road' and road:GetAttribute('NodeCount')==3)
assert(#road.Geometry.Sidewalks:GetChildren()==0)
local geometry,nodes=road.Geometry,road.Nodes
assert(not pcall(function() Roads.rebuild(road,curved,{Width=3,Lanes=6}) end))
assert(not pcall(function() Roads.rebuild(road,{r.Vector3.zero,r.Vector3.new(10,20,0)},{}) end))
assert(road.Geometry==geometry and road.Nodes==nodes,'Failed edit replaced valid road data')
local loaded=r.deserializeModel(r.serializeModel({road},true))[1]
for i,p in Roads.points(loaded) do assert(near(p,curved[i]),'Saved road lost centerline') end
Roads.rebuild(loaded,Roads.points(loaded),Roads.config(loaded))
assert(loaded:GetAttribute('ObjectId')=='stable-road')
local preview=Roads.preview(curved,{})
for _,p in preview:GetDescendants() do if p:IsA('BasePart') then assert(not p.CanCollide and not p.CanQuery and p.Transparency>0) end end
local map=Guides.create()
assert(not map:GetAttribute('Calibrated') and #map.Tiles:GetChildren()==1)
Guides.update(map,1200,30,.75)
local oldFrame=map.Root.CFrame
local a,b=oldFrame*r.Vector3.new(-100,0,0),oldFrame*r.Vector3.new(100,0,0)
local width=map:GetAttribute('Width')
local factor=Guides.calibrate(map,a,b,100)
assert(math.abs(factor-100*Path.StudsPerMeter/200)<.0001)
assert(near(map.Root.CFrame*r.Vector3.new(-100*factor,0,0),a),'Calibration moved its first anchor')
assert(math.abs(map:GetAttribute('Width')-width*factor)<.001 and map:GetAttribute('Calibrated'))
Guides.update(map,map:GetAttribute('Width'),30,.5)
assert(map:GetAttribute('Calibrated'),'Opacity change lost calibration')
Guides.update(map,4000,0,.5)
assert(not map:GetAttribute('Calibrated') and #map.Tiles:GetChildren()==4)
for _,tile in map.Tiles:GetChildren() do
	assert(tile.Size.X<=2000 and tile.Size.Z<=2000 and not tile.CanCollide and not tile.CanQuery)
	assert(near(tile.CFrame:VectorToWorldSpace(-r.Vector3.xAxis),-r.Vector3.xAxis),'Map image right is rotated/mirrored')
	assert(near(tile.CFrame:VectorToWorldSpace(-r.Vector3.zAxis),-r.Vector3.zAxis),'Map image down is rotated/mirrored')
	assert(tile.ReferenceImage:IsA('Texture'),'Map must not use a depth-biased SurfaceGui')
	local localCenter=map.Root.CFrame:PointToObjectSpace(tile.CFrame.Position)
	assert(localCenter.X*(.5-tile:GetAttribute('U0')-.25)>0,'Map tile columns run opposite to image UVs')
end
Guides.visible(map,false)
for _,item in map:GetDescendants() do if item:IsA('Texture') then assert(item.Transparency==1) end end
local oldTiles=map.Tiles
assert(not pcall(function() Guides.calibrate(map,a,a,100) end))
assert(map.Tiles==oldTiles,'Invalid calibration replaced the map')
local compiler=require('@lune/luau')
for _,name in {'RoadPath','RoadNetworkFactory','RoadJunctions','RoadNetwork','MapGuideFactory','RoadEditorPlugin.server','RoadGuideRuntime.server'} do compiler.compile(fs.readFile('src/'..name..'.luau')) end
print('PASS: continuous road area, horizontal collision surfaces, curves/grades, identity, rollback, saved editable centerlines, preview isolation, tiled maps, anchored calibration, source compile.')
