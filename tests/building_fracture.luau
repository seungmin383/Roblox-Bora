local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local F=require('../src/BuildingFracture')(r)
local V,C=r.Vector3,r.CFrame
local place=r.deserializePlace(fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*',''))
local workspace=place:GetService('Workspace')
local start=workspace.CenterSpawn.CFrame*C.new(0,3,0)
local grass=workspace.GrassPlain
local function onGrass(world)
	local p=grass.CFrame:PointToObjectSpace(world);local half=grass.Size*.5
	if math.abs(p.X)>half.X or math.abs(p.Z)>half.Z then return nil end
	return grass.CFrame.Y+half.Y
end
local function projectSize(relative,half)
	local x,y,z=relative.RightVector,relative.UpVector,relative.LookVector
	return V.new(math.abs(x.X)*half.X+math.abs(y.X)*half.Y+math.abs(z.X)*half.Z,
		math.abs(x.Y)*half.X+math.abs(y.Y)*half.Y+math.abs(z.Y)*half.Z,
		math.abs(x.Z)*half.X+math.abs(y.Z)*half.Y+math.abs(z.Z)*half.Z)
end
local function occupied(cf,size)
	local half=(size+V.new(2,-.4,2))*.5
	for _,part in workspace:GetDescendants() do
		if part:IsA('BasePart') and not part:IsA('Terrain') and part.CanCollide then
			local relative=cf:ToObjectSpace(part.CFrame)
			local p=relative.Position;local h=projectSize(relative,part.Size*.5)+half
			if math.abs(p.X)<h.X and math.abs(p.Y)<h.Y and math.abs(p.Z)<h.Z then return true end
		end
	end
	return false
end
local front=assert(F.frontWall(start,onGrass,occupied),'No placement in front of the saved spawn')
assert(math.abs((front.Position-start.Position):Dot(start.LookVector)-13)<.001)
assert(front.RightVector:Dot(-start.LookVector)>.99 and not occupied(front,F.TestSize))
local alternate=assert(F.frontWall(start,onGrass,function(cf) return (cf.Position-start.Position):Dot(start.LookVector)<17 end))
assert(math.abs((alternate.Position-start.Position):Dot(start.LookVector)-18)<.001)
assert(not F.frontWall(start,function() return nil end,occupied))
local villa=workspace.BoraNeighborhood_01.Buildings.BoraVilla
local interior=villa.Geometry.FloorPlanInterior
local original=assert(F.findWall(interior,2),'No testable 2F partition in the saved villa')
assert(original.Name=='WallStart' or original.Name=='WallEnd' or original.Name:match('^PlanWall_'))
local fixed,loose=F.layout(original.Size)
local area=0
for _,group in {fixed,loose} do for _,rect in group do
	assert(rect.H>.05 and rect.W>.05);area+=rect.H*rect.W
end end
assert(math.abs(area-original.Size.Y*original.Size.Z)<.001,'Fractured sections no longer cover the original volume')
local base,originalHeight=original.CFrame,original.Size.Y
local worldBefore={}
for _,item in villa:GetDescendants() do if item~=original then worldBefore[item]=item.Parent end end
local room,newNormal=r.Instance.new('Folder'),base.RightVector
local kicks,wedgeCount=0,0;local remove=nil
local effects={
	Expire=function(item,secs) assert(secs==9);remove=item end,
	Kick=function(part,direction,spin)
		assert(not part.Anchored and part.CanCollide and direction:Dot(newNormal)<-8)
		assert(spin.Magnitude<5 and part:IsDescendantOf(room));kicks+=1
		if part:IsA('WedgePart') then wedgeCount+=1 end
	end,
}
local result=assert(F.breakWall(original,base.Position+newNormal*4,room,effects))
assert(result.Count==16 and kicks==16 and wedgeCount==8 and remove==result.Rubble)
assert(#result.Remainder:GetChildren()==9 and #result.Rubble:GetChildren()==16)
for item,parent in worldBefore do assert(item.Parent==parent,'Unrelated villa object moved: '..item.Name) end
assert(not F.breakWall(original,base.Position,room,effects))
for _,part in result.Remainder:GetChildren() do
	assert(part.Anchored and part.CanCollide)
	local localFrame=base:ToObjectSpace(part.CFrame)
	local half=part.Size*.5
	-- A rectangle at the centre of the broken wall remains passable. The
	-- retained side strips may be jagged but cannot protrude into this gap.
	assert(math.abs(localFrame.Z)>half.Z+2.4 or localFrame.Y-half.Y>=-originalHeight*.5+7.3)
end
assert(F.findWall(interior,3),'The corresponding 3F wall was lost')
local demo=compiler.load(fs.readFile('src/BuildingFractureDemo.server.luau'))
local serviceCalls=0
setfenv(demo,setmetatable({game={GetService=function(_,name)
	serviceCalls+=1;assert(name=='RunService');return {IsStudio=function() return false end}
end}},{__index=getfenv()}))
demo();assert(serviceCalls==1,'The Studio test accessed the released game')
print('PASS: clear test panel 13 studs in front of saved spawn, obstruction fallback, irregular opening, 16 falling fragments, cleanup and unchanged geometry.')
