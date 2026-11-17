local r,fs=require('@lune/roblox'),require('@lune/fs')
local Path=require('../src/RoadPath')(r.Vector3)
local Roads=require('../src/RoadNetworkFactory')(r,Path)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J)
local V=r.Vector3.new
local function close(a,b) return (a-b).Magnitude<.001 end
local function scene()
	local folder=r.Instance.new('Folder'); folder.Name='BoraRoads'
	local h=Roads.create({V(-120,0,0),V(120,0,0)},{Curve=0},'host'); h.Name='Host'; h.Parent=folder
	local b=Roads.create({V(0,0,100),V(0,0,3)},{Curve=0},'branch'); b.Name='Branch'; b.Parent=folder
	return folder,h,b
end
local f,h,b=scene()
local ep,endpointLink=N.snap(f,V(-118,0,1),b)
assert(close(ep,V(-120,0,0)) and endpointLink==nil,'Existing endpoint snapping regressed')
local p,link=N.snap(f,V(0,0,3),b)
assert(close(p,V(0,0,0)) and link.Host==h and math.abs(link.At-.5)<.001,'Interior snap missed host centerline')
assert(N.edit(f,b,Roads.points(b),Roads.config(b),true)==1)
assert(#N.links(b)==1 and N.links(b)[1].End=='End' and close(Roads.points(b)[2],V(0,0,0)))
assert(#f.Junctions:GetChildren()==1 and h:GetAttribute('JunctionCut') and b:GetAttribute('JunctionCut'))
local plan=J.plan(Path.sample(Roads.points(h),Roads.config(h)),Path.sample(Roads.points(b),Roads.config(b)),.5,'End')
assert(#plan.Bands==21 and #plan.Perimeter==24,'Rounded curb samples missing')
local area,volume=0,0
for i,p2 in plan.Perimeter do
	local q=plan.Perimeter[i%#plan.Perimeter+1]; area+=(p2.X*q.Z-p2.Z*q.X)*.5
end
for _,part in f.Junctions:GetChildren()[1].Asphalt:GetChildren() do
	assert(part.Anchored and part.CanCollide and part.CanQuery and math.abs(part.CFrame.RightVector.Y)>.999)
	volume+=part.Size.X*part.Size.Y*part.Size.Z*.5
end
assert(math.abs(volume-math.abs(area)*.6)<.05,'Junction fan has missing/duplicate collidable asphalt area')
local trimmed=Path.segments(Path.sample(Roads.points(h),Roads.config(h)),{plan.HostCut})
for _,s in trimmed do assert(s[2].Distance<=plan.HostCut[1]+.001 or s[1].Distance>=plan.HostCut[2]-.001,'Host surface crosses junction cut') end
for _,arm in plan.Arms do
	local foundLeft,foundRight=false,false
	for _,p2 in plan.Perimeter do foundLeft=foundLeft or close(p2,arm.Left); foundRight=foundRight or close(p2,arm.Right) end
	assert(foundLeft and foundRight,'Junction does not meet an approach portal')
end
for _,road in {h,b} do
	for _,mark in road.Geometry.Markings:GetChildren() do
		local p2=mark.CFrame.Position
		if road==h then assert(math.abs(p2.X)>=plan.HostCut[2]-120-.01,'Center line enters junction')
		else assert(p2.Z>=100-plan.BranchCut[1]-.01,'Branch center line enters junction') end
	end
end
local id=b:GetAttribute('ObjectId')
N.edit(f,h,{V(-120,0,20),V(120,0,20)},Roads.config(h),false)
assert(close(Roads.points(b)[2],V(0,0,20)) and b:GetAttribute('ObjectId')==id,'Branch did not follow host movement')
N.edit(f,b,Roads.points(b),{Width=10,Lanes=2,Sidewalk=2,Curve=0,Lift=.2},false)
assert(math.abs(Roads.points(b)[2].Y+(.2-.05)*Path.StudsPerMeter)<.001,'Connected asphalt heights no longer agree')
local loaded=r.deserializeModel(r.serializeModel({f},true))[1]
assert(N.links(loaded.Branch)[1].Host==loaded.Host,'Saved junction lost its host reference')
N.apply(loaded)
assert(#loaded.Junctions:GetChildren()==1,'Reload did not rebuild junction')
local oldGeometry,oldJunction=h.Geometry,f.Junctions
assert(not pcall(function() N.edit(f,h,{V(-5,0,0),V(5,0,0)},Roads.config(h),false) end))
assert(h.Geometry==oldGeometry and f.Junctions==oldJunction,'Invalid edit partially replaced the network')
-- Drag an attached endpoint away: restore both roads and remove the patch.
N.edit(f,b,{V(0,0,100),V(40,0,80)},Roads.config(b),true)
assert(#N.links(b)==0 and #f.Junctions:GetChildren()==0 and not h:GetAttribute('JunctionCut'),'Detached junction left a curb gap')
-- The opposite endpoint and unequal approach widths also work.
local f2,h2,b2=scene()
N.edit(f2,b2,{V(10,0,0),V(70,0,-100)},{Width=4,Lanes=1,Sidewalk=0,Curve=0},true)
assert(N.links(b2)[1].End=='Start' and #f2.Junctions:GetChildren()==1)
-- Closely spaced T mouths must fail atomically instead of merging trim holes.
local b3=Roads.create({V(30,0,0),V(30,0,100)},{Curve=0},'second'); b3.Parent=f2
local untouched=h2.Geometry
assert(not pcall(function() N.edit(f2,b3,Roads.points(b3),Roads.config(b3),true) end))
assert(h2.Geometry==untouched and #N.links(b3)==0)
-- Height-separated roads do not snap to one another.
local _,above=N.snap(f2,V(0,30,0),b3); assert(above==nil)
-- Curved-host motion follows sampled geometry rather than the raw control cage.
local f3,h3,b4=scene()
N.edit(f3,b4,{V(0,0,100),V(0,0,40)},Roads.config(b4),false)
N.edit(f3,h3,{V(-120,0,0),V(0,0,15),V(120,0,0)},{Curve=70},false)
N.edit(f3,b4,{V(0,0,100),V(0,0,15)},Roads.config(b4),true)
assert(#f3.Junctions:GetChildren()==1)
N.edit(f3,h3,{V(-120,0,0),V(0,0,30),V(120,0,0)},Roads.config(h3),false)
assert(close(Roads.points(b4)[2],V(0,0,30)))
local beforeCycle=h3.Geometry
assert(not pcall(function() N.apply(f3,h3,Roads.points(h3),Roads.config(h3),{{Host=b4,At=.5,End='Start'}}) end))
assert(h3.Geometry==beforeCycle,'Cyclic edit partially changed geometry')
h3.Parent=nil
N.apply(f3)
assert(#f3.Junctions:GetChildren()==0 and not b4:GetAttribute('JunctionCut'),'Refresh did not restore the road after its host was removed')
for _,name in {'RoadJunctions','RoadNetwork','RoadEditorPlugin.server'} do require('@lune/luau').compile(fs.readFile('src/'..name..'.luau')) end
print('PASS: T interior snapping, exact portal cuts, rounded curbs, trimmed markings, persistent references, host/width/height edits, detach restoration, invalid/overlap rollback, angled/curved approaches, grade separation, compile.')
