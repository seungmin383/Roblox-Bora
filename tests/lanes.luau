local r,fs=require('@lune/roblox'),require('@lune/fs')
local Path=require('../src/RoadPath')(r.Vector3)
local L=require('../src/LaneDirections')(r,Path)
local Traffic=require('../src/RoadTraffic')(r,Path,L,require('../src/TrafficAssetLayout'))
local Roads=require('../src/RoadNetworkFactory')(r,Path,Traffic)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J,Traffic,L)
local V=r.Vector3.new
local function road(folder,id,points,config)
	local model=Roads.create(points,config or {Curve=0},id);model.Name=id;model.Parent=folder;return model
end
local function entry(folder,model,sign,key)
	for _,item in L.entries(folder,model) do if item.Sign==sign and (not key or item.Key==key) then return item end end
	error('Approach not found')
end
local function set(folder,model,sign,lane,mask,key)
	local e=entry(folder,model,sign,key);N.setLane(folder,e.Junction,model,sign,lane,mask);return entry(folder,model,sign,e.Key)
end
local function scene()
	local f=r.Instance.new('Folder')
	local a=road(f,'A',{V(-210,0,0),V(210,0,0)},{Curve=0,Width=21,Lanes=6})
	local b=road(f,'B',{V(0,0,-210),V(0,0,210)},{Curve=0,Width=14,Lanes=4})
	N.apply(f);return f,a,b
end
local f,a,b=scene()
assert(#L.entries(f)==4 and #L.entries(f,a)==2)
for _,e in L.entries(f,a) do assert(e.Count==3 and e.Available==7 and e.ArrowVisible) end
local key=entry(f,a,1).Key
set(f,a,1,1,2);set(f,a,1,2,1);set(f,a,1,3,4)
set(f,b,-1,1,3);set(f,b,-1,2,5)
local selected=entry(f,a,1)
assert(selected.Key==key and selected.Masks[1]==2 and selected.Masks[3]==4)
assert(entry(f,a,-1).Masks[1]==1,'Opposite approach was edited')
for mask=1,7 do set(f,a,-1,1,mask);assert(entry(f,a,-1).Masks[1]==mask) end
local patch=f.Junctions:GetChildren()[1]
local arrows=0
for _,mark in patch.Markings:GetChildren() do
	if mark.Name=='LaneArrow' then arrows+=1;assert(mark:GetAttribute('Lane')>=1 and mark:GetAttribute('Directions')>=1) end
	for _,part in mark:GetChildren() do assert(part.Anchored and not part.CanCollide and not part.CanQuery) end
end
assert(arrows>20 and #patch.Signals:GetChildren()==4 and #patch.PedestrianSignals:GetChildren()==8)
local saved=r.deserializeModel(r.serializeModel({f},true))[1]
N.apply(saved)
assert(entry(saved,saved.A,1).Masks[1]==2 and entry(saved,saved.A,1).Key==key,'Save/reload lost lane rules')
-- Width changes and moving the crossing along its host preserve the road/sign.
N.edit(f,a,Roads.points(a),{Curve=0,Width=18,Lanes=6},false)
N.edit(f,b,{V(60,0,-210),V(60,0,210)},Roads.config(b),false)
assert(entry(f,a,1).Masks[1]==2 and entry(f,a,1).Masks[3]==4 and entry(f,a,1).Key==key)
local old,serial=f.Junctions,f:GetAttribute('LaneSerial')
for _,bad in {{1,0},{1,8},{4,1}} do
	local e=entry(f,a,1)
	assert(not pcall(function() N.setLane(f,e.Junction,a,1,bad[1],bad[2]) end))
	assert(f.Junctions==old and f:GetAttribute('LaneSerial')==serial,'Invalid direction edit partially changed the network')
end
-- Odd lane totals: two toward the end point, one toward the start point.
local odd=r.Instance.new('Folder')
local oa=road(odd,'Odd',{V(-180,0,0),V(180,0,0)},{Curve=0,Width=10.5,Lanes=3})
local ob=road(odd,'Other',{V(0,0,-180),V(0,0,180)})
N.apply(odd)
assert(entry(odd,oa,-1).Count==2 and entry(odd,oa,1).Count==1)
local layout=Path.lanes(Roads.config(oa),1)
assert(math.abs(layout.Divider+1.75*Path.StudsPerMeter)<.001)
for _,line in oa.Geometry.Markings:GetChildren() do if line.Name=='CenterLine' then assert(math.abs(line.CFrame.Position.Z-layout.Divider)<.001) end end
-- T exit validation, then merge an opposite branch and remove it again.
local t=r.Instance.new('Folder')
local host=road(t,'Host',{V(-180,0,0),V(180,0,0)})
local branch=road(t,'Branch',{V(0,0,160),V(0,0,0)})
N.edit(t,branch,Roads.points(branch),Roads.config(branch),true)
local e=entry(t,branch,-1);assert(e.Available==6)
local untouched=t.Junctions
assert(not pcall(function() N.setLane(t,e.Junction,branch,-1,1,1) end));assert(t.Junctions==untouched)
e=set(t,branch,-1,1,2);local tkey=e.Key
local opposite=road(t,'Opposite',{V(0,0,-160),V(0,0,0)})
N.edit(t,opposite,Roads.points(opposite),Roads.config(opposite),true)
assert(entry(t,branch,-1).Key==tkey and entry(t,branch,-1).Masks[1]==2)
opposite.Parent=nil;N.apply(t)
assert(entry(t,branch,-1).Key==tkey and entry(t,branch,-1).Masks[1]==2)
-- Several junctions of the same road pair retain their own definitions.
local multi=r.Instance.new('Folder')
local ma=road(multi,'MultiA',{V(-260,0,0),V(260,0,0)})
local mb=road(multi,'MultiB',{V(-120,0,-150),V(-120,0,150),V(0,0,150),V(0,0,-150),V(120,0,-150),V(120,0,150)})
N.apply(multi)
local middle
for _,candidate in L.entries(multi,ma) do if candidate.Sign==1 and math.abs(candidate.Junction:GetAttribute('Center').X)<1 then middle=candidate end end
assert(middle);set(multi,ma,1,1,4,middle.Key)
local shifted={};for _,p in Roads.points(mb) do table.insert(shifted,p+V(20,0,0)) end
N.edit(multi,mb,shifted,Roads.config(mb),false)
assert(entry(multi,ma,1,middle.Key).Masks[1]==4)
local seen=0
for _,candidate in L.entries(multi,ma) do if candidate.Sign==1 then
	if candidate.Key==middle.Key then assert(candidate.Masks[1]==4) else assert(candidate.Masks[1]==1) end;seen+=1
end end
assert(seen==3)
-- A new crossing from another road must not renumber another junction's rules.
local extra=road(multi,'Extra',{V(-210,0,-150),V(-210,0,150)})
N.apply(multi);assert(entry(multi,ma,1,middle.Key).Masks[1]==4)
-- Lane narrowing drops nonexistent lane slots and retains the inner lane.
N.edit(f,a,Roads.points(a),{Curve=0,Width=14,Lanes=4},false)
assert(entry(f,a,1).Count==2 and entry(f,a,1).Masks[1]==2)
-- Disconnected intersections remove their arrows and direction records.
N.edit(f,b,{V(500,0,-210),V(500,0,210)},Roads.config(b),false)
assert(#L.entries(f)==0 and #f.Junctions:GetChildren()==0)
-- Export a composed arrow preview, never another Place.
local visual,va,vb=scene()
set(visual,va,1,1,2);set(visual,va,1,2,1);set(visual,va,1,3,4)
set(visual,vb,-1,1,3);set(visual,vb,-1,2,5)
-- Arrow polygons stay inside the selected incoming lane, behind the stop line.
local da,db=Path.sample(Roads.points(va),Roads.config(va)),Path.sample(Roads.points(vb),Roads.config(vb))
local plan=J.planApproaches({{Data=da,At=.5,State={Road=va}},{Data=db,At=.5,State={Road=vb}}})
L.bind({plan},visual.Junctions,visual:GetAttribute('LaneSerial'))
local decoration=Traffic.plan(plan,Traffic.config(visual))
for _,mark in decoration.Markings do if mark.Kind=='LaneArrow' then
	local arm=plan.Arms[mark.Arm];local layout=Path.lanes(arm.Data.Config,arm.Sign)
	for _,p in mark.Corners do
		local q,at=Path.project(arm.Data,p);local s=Path.at(arm.Data,at)
		local lateral=(p-q):Dot(s.Side*arm.Sign)
		assert(math.abs(lateral-layout.Centers[mark.Lane])<layout.Width*.49,'Arrow leaves its incoming lane')
		local outward=(at-arm.Anchor)*arm.Sign-arm.Trim
		assert(outward>5.3*Path.StudsPerMeter,'Arrow overlaps the stop/crosswalk zone')
	end
end end
for approach,model in {va,vb} do for _,line in model.Geometry.Markings:GetChildren() do
	local _,at=Path.project(if model==va then da else db,line.CFrame.Position)
	for _,cut in decoration.Cuts do if cut.Approach==approach then assert(at<=cut.Range[1]+.001 or at>=cut.Range[2]-.001,'Lane divider enters arrow zone') end end
end end
fs.writeFile('dist/LaneDirectionsJunction.rbxmx',r.serializeModel({visual},true))
for _,name in {'LaneDirections','RoadNetwork','RoadTraffic','RoadEditorPlugin.server'} do require('@lune/luau').compile(fs.readFile('src/'..name..'.luau')) end
print('PASS: direction combinations, per-approach isolation, road references/save/reload, odd lane split/divider, T exits/merge/delete, width/movement/multiple crossings, narrowing, atomic invalid edits, noncolliding arrows, unchanged signal counts.')
