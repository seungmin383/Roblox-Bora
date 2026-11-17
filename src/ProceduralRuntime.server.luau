-- Restore saved recipes once per play session. No per-frame tree loop.
local Parameters=require(script.TreeParameters)
local Skeleton=require(script.TreeSkeleton)(Vector3,Parameters)
local Mesher=require(script.TreeMesher)(Vector3)
local catalog=require(script.TreeAssetCatalog)
local api={Instance=Instance,Vector3=Vector3,CFrame=CFrame,Color3=Color3,Enum=Enum,UDim2=UDim2}
api.BuildWood=require(script.TreeMeshBackend)(game:GetService('AssetService'),Content,Vector3,Vector2,Color3,Enum,catalog.ProceduralBark)
local factory=require(script.ProceduralTreeFactory)(api,require(script.GrowthMath),catalog,Parameters,Skeleton,Mesher)
local folder=workspace:FindFirstChild('BoraTrees')
if not folder then return end
local function restore(tree)
	if not factory.isTree(tree) or tree:GetAttribute('SchemaVersion')~=4 or not tree:GetAttribute('LiveMesh') then return end
	local ok,err=pcall(function() factory.rebuild(tree,Parameters.fromModel(tree),function() task.wait() end) end)
	if ok then print('[BoraTree] runtime restored '..(tree:GetAttribute('ObjectId') or tree.Name)) else warn('[BoraTree] runtime: '..tostring(err)) end
end
for _,tree in folder:GetChildren() do restore(tree) end
folder.ChildAdded:Connect(restore)
