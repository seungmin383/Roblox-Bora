-- Read-only survey of the user's sole Place. Never serialize a Place.
local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local place=r.deserializePlace(fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*',''))
local world=place:GetService('Workspace')
local Path=require('../src/RoadPath')(r.Vector3)
local Roads=require('../src/RoadNetworkFactory')(r,Path)
local function v(p) return {p.X,p.Y,p.Z} end
local function attrs(item)
	local a={}
	for k,value in item:GetAttributes() do
		if typeof(value)=='Vector3' then a[k]=v(value)
		elseif type(value)=='number' or type(value)=='string' or type(value)=='boolean' then a[k]=value end
	end
	return a
end
local report={World={},Roads={},Junctions={},Obstacles={}}
for _,item in world:GetChildren() do
	table.insert(report.World,{Name=item.Name,Class=item.ClassName,Children=#item:GetChildren()})
end
local roads=world.BoraRoads
for _,road in roads:GetChildren() do
	if road:FindFirstChild('Nodes') then
		local points={}
		for _,node in road.Nodes:GetChildren() do table.insert(points,{Name=node.Name,P=v(node.Value)}) end
		local samples={}
		for _,sample in Path.sample(Roads.points(road),Roads.config(road)).Samples do table.insert(samples,v(sample.P)) end
		table.insert(report.Roads,{Name=road.Name,Attributes=attrs(road),Points=points,Samples=samples})
	end
end
for _,j in roads.Junctions:GetChildren() do
	local o={Name=j.Name,Attributes=attrs(j),Groups={}}
	o.Members={}
	for _,ref in j.Members:GetChildren() do table.insert(o.Members,{Name=ref.Name,RoadId=ref.Value:GetAttribute('ObjectId'),Attributes=attrs(ref)}) end
	for _,group in j:GetChildren() do
		local n=0;local lo=r.Vector3.new(math.huge,math.huge,math.huge);local hi=-lo
		for _,p in group:GetDescendants() do if p:IsA('BasePart') then
			n+=1;lo=lo:Min(p.CFrame.Position);hi=hi:Max(p.CFrame.Position)
		end end
		o.Groups[group.Name]={Parts=n,Min=if n>0 then v(lo) else nil,Max=if n>0 then v(hi) else nil}
	end
	table.insert(report.Junctions,o)
end
for _,p in world:GetDescendants() do
	if p:IsA('BasePart') and not p:IsDescendantOf(roads) and p.Transparency<1 and p.Size.Magnitude<500 then
		if p.Name=='Chassis' or p.Name=='SpawnLocation' or p.Parent.Name=='BoraTrees' or p:FindFirstChildOfClass('SpecialMesh') then
			table.insert(report.Obstacles,{Name=p.Name,P=v(p.CFrame.Position),Size=v(p.Size)})
		end
	end
end
fs.writeFile('dist/neighborhood-survey.json',serde.encode('json',report,true))
print(serde.encode('json',{World=report.World,Roads=report.Roads,Junctions=report.Junctions},true))
