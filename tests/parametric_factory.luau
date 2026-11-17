local r,fs=require('@lune/roblox'),require('@lune/fs')
local Parameters=require('../src/TreeParameters')
local Skeleton=require('../src/TreeSkeleton')(r.Vector3,Parameters)
local Mesher=require('../src/TreeMesher')(r.Vector3)
local rules=require('../src/GrowthMath')
local service={Created={},Destroyed=0}
function service:CreateEditableMesh()
	local mesh={Vertices={},Faces={}}
	function mesh:AddVertex(v) table.insert(self.Vertices,v); return #self.Vertices end
	function mesh:AddNormal(v) return 1 end
	function mesh:AddUV(v) return 1 end
	function mesh:AddTriangle(a,b,c) table.insert(self.Faces,{a,b,c}); return #self.Faces end
	function mesh:SetFaceNormals() end
	function mesh:SetFaceUVs() end
	function mesh:Destroy() service.Destroyed+=1 end
	return mesh
end
function service:CreateDataModelContentAsync(mesh) assert(#mesh.Faces<=18000); return 'Success',mesh end
function service:CreateMeshPartAsync(mesh)
	table.insert(self.Created,mesh)
	return r.Instance.new('MeshPart')
end
local enums={CreateContentResult={Success='Success'},CollisionFidelity=r.Enum.CollisionFidelity}
local bake=require('../src/TreeMeshBackend')(service,{fromObject=function(v) return v end},r.Vector3,r.Vector2,r.Color3,enums,'rbxasset://BoraTreeKitV3/ProceduralBark.png')
local api={}; for k,v in r do api[k]=v end
api.BuildWood=bake
local factory=require('../src/ProceduralTreeFactory')(api,rules,{Leaf={Texture='rbxasset://BoraTreeKitV3/GinkgoCluster.png'}},Parameters,Skeleton,Mesher)
local base=r.CFrame.new(7,3,-12)*r.CFrame.Angles(0,.6,0)
local function nearFrame(a,b)
	local aa,bb={a:GetComponents()},{b:GetComponents()}
	for i,v in aa do if math.abs(v-bb[i])>.0001 then return false end end
	return true
end
local tree=factory.create({BranchCount=12,Growth=1,ObjectId='keep-this-id'},base)
assert(#tree.Geometry.Wood:GetChildren()==math.ceil(tree:GetAttribute('WoodTriangles')/18000),'API face budget was not partitioned')
assert(#service.Created==service.Destroyed,'Editable meshes leaked')
assert(#tree.Geometry.Leaves:GetChildren()==111,'Canopy did not follow branch graph')
local root,geometry=tree.Root,tree.Geometry
local leaves=geometry.Leaves:GetChildren()
for g=0,100 do
	factory.setGrowth(tree,g/100)
	assert(tree.Root==root and nearFrame(tree.Root.CFrame,base),'Growth moved the root')
	assert(tree.Geometry==geometry and geometry.Leaves:GetChildren()[1]==leaves[1],'Growth recreated geometry')
end
local originalWood=geometry.Wood:GetChildren()[1]
factory.rebuild(tree,{BranchCount=6,LeafDensity=0,Spread=1.2,Thickness=.9,Seed=71})
assert(tree:GetAttribute('BranchCount')==6 and #tree.Geometry.Leaves:GetChildren()==0,'Structure edit failed')
assert(tree:GetAttribute('ObjectId')=='keep-this-id' and tree.Root==root and nearFrame(tree.Root.CFrame,base),'Rebuild changed tree identity')
assert(tree:GetAttribute('Growth')==1,'Rebuild changed growth')
local stableGeometry=tree.Geometry
assert(not pcall(function() factory.rebuild(tree,{BranchCount=500}) end),'Invalid recipe accepted')
assert(tree.Geometry==stableGeometry,'Invalid edit destroyed the tree')
local validBackend=api.BuildWood
api.BuildWood=function() error('simulated mesh API failure') end
assert(not pcall(function() factory.rebuild(tree,{BranchCount=8}) end),'Expected API error')
assert(tree.Geometry==stableGeometry and tree:GetAttribute('BranchCount')==6,'API failure partially committed')
api.BuildWood=validBackend
-- Object-based content is session scoped: attributes are the durable source.
local restored=r.deserializeModel(r.serializeModel({tree},true))[1]
factory.rebuild(restored,Parameters.fromModel(restored))
assert(restored:GetAttribute('ObjectId')=='keep-this-id' and nearFrame(restored.Root.CFrame,base),'Saved recipe failed to restore')
assert(restored:GetAttribute('BranchCount')==6 and #restored.Geometry.Leaves:GetChildren()==0,'Saved structure changed')
local compiler=require('@lune/luau')
for _,name in {'TreeParameters','TreeSkeleton','TreeMesher','TreeMeshBackend','ProceduralTreeFactory','ParametricTreePlugin.server','ProceduralRuntime.server'} do compiler.compile(fs.readFile('src/'..name..'.luau')) end
print('PASS: mesh chunks, resource cleanup, continuous growth, identity, branch edit, density zero, failure rollback, saved recipe restore, compile.')
