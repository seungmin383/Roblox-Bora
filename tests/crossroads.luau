local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local Path=require('../src/RoadPath')(r.Vector3)
local Roads=require('../src/RoadNetworkFactory')(r,Path)
local J=require('../src/RoadJunctions')(r.Vector3,Path)
local N=require('../src/RoadNetwork')(r,Path,Roads,J)
local V=r.Vector3.new
local function near(a,b) return (a-b).Magnitude<.002 end
local function folder() return r.Instance.new('Folder') end
local function road(f,id,points,config)
	local model=Roads.create(points,config or {Curve=0},id); model.Name=id; model.Parent=f; return model
end
local function data(model) return Path.sample(Roads.points(model),Roads.config(model)) end
local function crossPlan(a,b)
	local da,db=data(a),data(b); local hits=Path.crossings(da,db)
	assert(#hits==1,'Crossing at shared samples must be reported once')
	return J.planApproaches({{Data=da,At=hits[1].A/da.Length},{Data=db,At=hits[1].B/db.Length}})
end
local function verifySurface(model,plan)
	local area,volume=0,0
	for i,p in plan.Perimeter do
		local q=plan.Perimeter[i%#plan.Perimeter+1]; area+=(p.X*q.Z-p.Z*q.X)*.5
	end
	for _,part in model.Asphalt:GetChildren() do
		assert(part.Anchored and part.CanCollide and part.CanQuery)
		volume+=part.Size.X*part.Size.Y*part.Size.Z*.5
	end
	assert(math.abs(volume-math.abs(area)*.6)<.1,'Missing or duplicated junction collision area')
	for _,arm in plan.Arms do
		local left,right=false,false
		for _,p in plan.Perimeter do left=left or near(p,arm.Left); right=right or near(p,arm.Right) end
		assert(left and right,'Portal does not match adjoining road')
	end
end
-- Two through roads: exact portals, four rounded corners and no markings inside.
local f=folder()
local a=road(f,'EastWest',{V(-160,0,0),V(0,0,0),V(160,0,0)})
local b=road(f,'NorthSouth',{V(0,0,-160),V(0,0,0),V(0,0,160)})
local count,stats=N.apply(f)
assert(count==1 and stats.Cross==1 and stats.T==0)
local patch=f.Junctions:GetChildren()[1]
assert(patch:GetAttribute('ArmCount')==4 and #patch.Members:GetChildren()==2)
local plan=crossPlan(a,b)
assert(#plan.Arms==4 and #plan.Bands==40 and #plan.Perimeter==44)
verifySurface(patch,plan)
for index,model in {a,b} do
	local cut=plan.Cuts[index]; local d=data(model)
	for _,segment in Path.segments(d,{cut}) do
		assert(segment[2].Distance<=cut[1]+.001 or segment[1].Distance>=cut[2]-.001)
	end
	for _,mark in model.Geometry.Markings:GetChildren() do
		local _,distance=Path.project(d,mark.CFrame.Position)
		assert(distance<=cut[1]+.01 or distance>=cut[2]-.01,'Lane line enters cross junction')
	end
end
-- Both widths and the host geometry are editable; moving apart restores curbs.
local originalB=b.Geometry
N.edit(f,a,Roads.points(a),{Width=12,Lanes=4,Sidewalk=2,Curve=0},false)
assert(b.Geometry~=originalB and #f.Junctions:GetChildren()==1)
N.edit(f,b,{V(60,0,-160),V(60,0,160)},Roads.config(b),false)
assert(near(f.Junctions:GetChildren()[1]:GetAttribute('Center'),V(60,.05*Path.StudsPerMeter,0)))
local restored=r.deserializeModel(r.serializeModel({f},true))[1]
local _,savedStats=N.apply(restored); assert(savedStats.Cross==1)
assert(restored.Junctions:GetChildren()[1].Members.Road1.Value.Parent==restored)
N.edit(f,b,{V(400,0,-160),V(400,0,160)},Roads.config(b),false)
assert(#f.Junctions:GetChildren()==0 and not a:GetAttribute('JunctionCut') and not b:GetAttribute('JunctionCut'))
-- Opposite T arms share the existing hub, including slightly offset clicks.
local t=folder()
local host=road(t,'Host',{V(-160,0,0),V(160,0,0)})
local south=road(t,'South',{V(0,0,130),V(0,0,2)})
N.edit(t,south,Roads.points(south),Roads.config(south),true)
local north=road(t,'North',{V(2,0,-130),V(2,0,-2)})
local p,link=N.snap(t,V(2,0,-2),north)
assert(near(p,V(0,0,0)) and link.Host==host and math.abs(link.At-.5)<.001)
local _,four=N.edit(t,north,Roads.points(north),Roads.config(north),true)
assert(four.Cross==1 and #t.Junctions:GetChildren()==1 and #t.Junctions:GetChildren()[1].Members:GetChildren()==3)
assert(N.links(north)[1].Host==host and N.links(south)[1].Host==host)
N.edit(t,host,{V(-160,0,20),V(160,0,20)},Roads.config(host),false)
assert(near(Roads.points(south)[2],V(0,0,20)) and near(Roads.points(north)[2],V(0,0,20)))
local reload=r.deserializeModel(r.serializeModel({t},true))[1]
local _,reloaded=N.apply(reload); assert(reloaded.Cross==1)
north.Parent=nil
local _,three=N.apply(t); assert(three.T==1 and three.Cross==0)
south.Parent=nil
N.apply(t); assert(#t.Junctions:GetChildren()==0 and not host:GetAttribute('JunctionCut'))
-- Multiple separated crossings along one road, including negative grid cells.
local multi=folder()
road(multi,'Trunk',{V(-320,0,0),V(320,0,0)})
road(multi,'Left',{V(-150,0,-120),V(-150,0,120)})
road(multi,'Right',{V(150,0,-120),V(150,0,120)})
local _,two=N.apply(multi); assert(two.Cross==2)
local curved=Path.sample({V(-160,0,-80),V(-80,0,80),V(80,0,-80),V(160,0,80)},{Curve=0})
local straight=Path.sample({V(-220,0,0),V(220,0,0)},{Curve=0})
assert(#Path.crossings(curved,straight)==3,'Repeated crossings were collapsed')
-- Unequal widths, oblique crossing and mildly curved approaches.
local angled=folder()
local ah=road(angled,'H',{V(-200,0,0),V(0,0,8),V(200,0,0)},{Curve=70,Width=9,Sidewalk=2})
local ab=road(angled,'B',{V(-80,0,-180),V(0,0,8),V(80,0,180)},{Curve=40,Width=6,Sidewalk=1})
assert(N.apply(angled)==1)
verifySurface(angled.Junctions:GetChildren()[1],crossPlan(ah,ab))
-- Grade-separated roads do not get an intersection, including Lift offsets.
local above=folder()
local ground=road(above,'Ground',{V(-140,0,0),V(140,0,0)})
local bridge=road(above,'Bridge',{V(0,10,-140),V(0,10,140)})
assert(N.apply(above)==0 and not ground:GetAttribute('JunctionCut'))
N.edit(above,bridge,{V(0,0,-140),V(0,0,140)},{Curve=0,Lift=1},false)
assert(#above.Junctions:GetChildren()==0)
-- Invalid shallow crossings and short approaches leave the old network intact.
local guard=folder()
local ga=road(guard,'A',{V(-160,0,0),V(160,0,0)})
local gb=road(guard,'B',{V(0,0,-160),V(0,0,160)})
N.apply(guard)
local oldA,oldB,oldPatch=ga.Geometry,gb.Geometry,guard.Junctions
for _,invalid in {{V(-140,0,-20),V(140,0,20)},{V(0,0,-5),V(0,0,160)}} do
	assert(not pcall(function() N.edit(guard,gb,invalid,Roads.config(gb),false) end))
	assert(ga.Geometry==oldA and gb.Geometry==oldB and guard.Junctions==oldPatch,'Invalid X partially committed')
end
local extra=road(guard,'Fifth',{V(0,0,0),V(100,0,100)})
assert(not pcall(function() N.edit(guard,extra,Roads.points(extra),Roads.config(extra),true) end))
assert(ga.Geometry==oldA and guard.Junctions==oldPatch and #N.links(extra)==0,'Five-arm rejection changed saved network')
extra.Parent=nil
-- Distinct nearby X hubs must not merge or overwrite one another's trim cuts.
local crowded=road(guard,'Close',{V(30,0,-140),V(30,0,140)})
assert(not pcall(function() N.apply(guard) end))
assert(ga.Geometry==oldA and guard.Junctions==oldPatch)
crowded.Parent=nil
-- An unrelated saved model is never rewritten by junction recomputation.
local far=road(guard,'Far',{V(1000,0,0),V(1200,0,0)})
local untouched=far.Geometry; N.apply(guard); assert(far.Geometry==untouched)
local function coords(v) return {v.X,v.Y,v.Z} end
local outline={}; for _,p2 in plan.Perimeter do table.insert(outline,coords(p2)) end
local bands={}; for _,band in plan.Bands do local points={}; for _,p2 in band do table.insert(points,coords(p2)) end; table.insert(bands,points) end
fs.writeFile('dist/cross-junction-geometry.json',serde.encode('json',{Center=coords(plan.Center),Perimeter=outline,Bands=bands,Arms=#plan.Arms},true))
print('PASS: automatic X, merged opposite T, four curbs, collision area/portals, trimmed lines, movement/width, detach/delete restoration, persistence, multiple/curved/oblique crossings, grade separation, atomic invalid/five-arm/close rejection, untouched unrelated geometry.')
