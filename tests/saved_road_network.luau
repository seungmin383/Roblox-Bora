-- Read the single saved project into memory; never serialize/write a Place.
local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local Path=require('../src/RoadPath')(r.Vector3)
local Lanes=require('../src/LaneDirections')(r,Path)
local Traffic=require('../src/RoadTraffic')(r,Path,Lanes,require('../src/TrafficAssetLayout'))
local Roads=require('../src/RoadNetworkFactory')(r,Path,Traffic)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J,Traffic,Lanes)
-- Lune's format detector expects the roblox root before any XML declaration.
local xml=fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*','')
local place=r.deserializePlace(xml)
local workspace=place:GetService('Workspace')
local folder=workspace:FindFirstChild('BoraRoads')
assert(folder,'Saved project has no roads')
local recipes={}
for _,road in folder:GetChildren() do if Roads.isRoad(road) then
	local nodes={}; for _,p in Roads.points(road) do table.insert(nodes,{p.X,p.Y,p.Z}) end
	table.insert(recipes,{Id=road:GetAttribute('ObjectId'),Points=nodes,Config=Roads.config(road)})
end end
fs.writeFile('dist/saved-road-recipes.json',serde.encode('json',recipes,true))
local ok,count,stats=pcall(N.apply,folder)
if not ok then
	local bare=require('../src/RoadNetwork')(r,Path,Roads,J)
	local baseOk,baseError=pcall(bare.apply,folder)
	print('BASE NETWORK:',baseOk,baseError)
	error(count)
end
local pedestrianCount=0
for _,junction in folder.Junctions:GetChildren() do pedestrianCount+=#junction.PedestrianSignals:GetChildren() end
local laneApproaches=#Lanes.entries(folder)
fs.writeFile('dist/saved-road-traffic-validation.json',serde.encode('json',{RoadCount=#recipes,Junctions=count,Stats=stats,PedestrianHeads=pedestrianCount,LaneApproaches=laneApproaches,Recipes=recipes,Mode='Read-only project; regenerated only in memory'},true))
print('PASS: saved project network regenerates in memory: '..#recipes..' roads, '..stats.T..' T, '..stats.Cross..' X, '..pedestrianCount..' pedestrian heads, '..laneApproaches..' lane approaches. Ro.rbxlx was not written.')
