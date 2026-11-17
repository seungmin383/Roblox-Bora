local r=require('@lune/roblox')
local Parameters=require('../src/TreeParameters')
local Skeleton=require('../src/TreeSkeleton')(r.Vector3,Parameters)
local Mesher=require('../src/TreeMesher')(r.Vector3)
local Factory=require('../src/ProceduralTreeFactory')(r,require('../src/GrowthMath'),{Leaf={Texture='test'}},Parameters,Skeleton,Mesher)
local fs,serde=require('@lune/fs'),require('@lune/serde')
local function validate(data)
	assert(#data.Faces<150000,'Unexpected geometry budget: '..#data.Faces)
	local edges={}; local volume=0
	for _,f in data.Faces do
		local a,b,c=data.Vertices[f[1]],data.Vertices[f[2]],data.Vertices[f[3]]
		assert((b-a):Cross(c-a).Magnitude>0,'Degenerate triangle')
		volume+=a:Dot(b:Cross(c))/6
		for i=1,3 do
			local a,b=f[i],f[i%3+1]
			local key=math.min(a,b)..':'..math.max(a,b)
			local e=edges[key] or {Count=0,Direction=0}
			e.Count+=1; e.Direction+=if a<b then 1 else -1; edges[key]=e
		end
	end
	for key,e in edges do assert(e.Count==2 and e.Direction==0,'Open/nonmanifold edge '..key..' count '..e.Count) end
	assert(volume>0,'Inverted surface')
	assert(math.abs(data.Center.Y-data.Bounds.Y/2)<.002,'Ground moved')
end
local cases={
	{Name='6',BranchCount=6}, {Name='9',BranchCount=9}, {Name='12',BranchCount=12},
	{Name='thin-wide',BranchCount=14,Thickness=.65,Spread=1.4},
	{Name='thick-narrow',BranchCount=4,Thickness=1.5,Spread=.65},
}
local dumps={}
for _,case in cases do
	local started=os.clock()
	local skeleton=Skeleton.build(case)
	assert(#skeleton.Branches==1+case.BranchCount*3,'Wrong branch graph')
	assert(#skeleton.Anchors==case.BranchCount*3+1,'Wrong canopy anchors')
	local data=Mesher.build(skeleton)
	validate(data)
	print(case.Name,#data.Vertices,#data.Faces,os.clock()-started)
	if case.Name=='6' or case.Name=='9' or case.Name=='12' then
		local function vec(v) return {v.X,v.Y,v.Z} end
		local dump={Vertices={},Normals={},Faces=data.Faces,UVs=data.UVs,Center=vec(data.Center),Bounds=vec(data.Bounds),Anchors={},Leaves={}}
		for _,v in data.Vertices do table.insert(dump.Vertices,vec(v)) end
		for _,n in data.Normals do table.insert(dump.Normals,vec(n)) end
		for _,a in skeleton.Anchors do table.insert(dump.Anchors,vec(a)) end
		for _,leaf in Factory.foliage(skeleton) do
			table.insert(dump.Leaves,{Center=vec(leaf.Center),Size=vec(leaf.Size),Frame={leaf.Rotation:GetComponents()},Tint=leaf.Tint})
		end
		dumps[case.Name]=dump
		-- Native mesh for a portable local Studio comparison place. Live edits use EditableMesh.
		local rows={'version 2.00\n',string.pack('<I2I1I1I4I4',12,40,12,#data.Vertices,#data.Faces)}
		for i,v in data.Vertices do
			local n=data.Normals[i]; local uv=data.UVs[i]
			table.insert(rows,string.pack('<ffffffffbbbbBBBB',v.X,v.Y,v.Z,n.X,n.Y,n.Z,uv[1],uv[2],0,0,0,127,255,255,255,255))
		end
		for _,f in data.Faces do table.insert(rows,string.pack('<I4I4I4',f[1]-1,f[2]-1,f[3]-1)) end
		fs.writeFile('assets/tree/local/Procedural'..case.Name..'.mesh',table.concat(rows))
	end
end
fs.writeFile('dist/parametric-geometry.json',serde.encode('json',dumps))
print('Exported baseline previews.')
for seed=1,8 do
	local config={Seed=seed*137,BranchCount=3+seed,Spread=if seed%2==0 then .65 else 1.4,Thickness=if seed%3==0 then .65 else 1.5}
	validate(Mesher.build(Skeleton.build(config)))
end
for _,bad in {{BranchCount=9.5},{BranchCount=100},{Spread=0},{Thickness=0/0},{Seed=-1}} do
	assert(not pcall(Parameters.normalize,bad),'Accepted invalid configuration')
end
print('PASS: branch graphs, connected closed oriented surfaces, ground pivot, limits, invalid input.')
