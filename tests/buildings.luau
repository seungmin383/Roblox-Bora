local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local P=require('../src/BuildingParameters');local F=require('../src/BuildingFactory')(r,P)
local V,C=r.Vector3,r.CFrame;local S=1/.28
local function near(a,b) assert((a-b).Magnitude<.001,tostring(a)..' != '..tostring(b)) end
local base=C.new(81,2,19)*C.Angles(0,1.2,0)
local b=F.create({Floors=1,Kind='Cafe',Title='새 이름 카페',Width=6,Depth=6},base)
assert(F.isBuilding(b) and b.Geometry.Floor_1 and not b.Geometry:FindFirstChild('Floor_2'))
assert(not b.Geometry:FindFirstChild('UpperMasonry'))
assert(b.Geometry.ShopSign.SignFace.Lettering.Text=='새 이름 카페')
local user=r.Instance.new('Part');user.Name='UserDecoration';user.CFrame=base*C.new(10,0,0);user.Parent=b
local sentinel=user.CFrame
local moved=C.new(-18,3,41)*C.Angles(0,-.7,0);b.BuildingOrigin.CFrame=moved
local old=F.rebuild(b,{Kind='Apartment',Floors=24,Title='보라 아파트 101',Balconies=true,Awning=false,Width=32,Depth=24,FloorHeight=4.2,GroundHeight=5,Sign=false})
assert(old.Parent==nil and user.Parent==b and user.CFrame==sentinel,'Manual decoration/root identity changed')
assert(b.Geometry.Floor_24 and not b.Geometry:FindFirstChild('Floor_25'))
assert(not b.Geometry:FindFirstChild('ShopSign') and not b.Geometry:FindFirstChild('Awning'))
near(b.Geometry.Floor_24.FloorSlab.CFrame.Position,(moved*C.new(0,(5+22*4.2-.09)*S,0)).Position)
assert(P.read(b).Floors==24 and P.read(b).Title=='보라 아파트 101')
local before=r.serializeModel({b},true)
for _,bad in {0/0,math.huge,-math.huge,'abc'} do
	assert(not pcall(F.rebuild,b,{Width=bad}));assert(r.serializeModel({b},true)==before,'Bad input mutated model')
end
assert(not pcall(P.normalize,{Wall='badhex'}));assert(not pcall(P.normalize,{Title=string.rep('가',49)}))
-- Edits retain each original root's identity/pose, recipe across save/reload.
local loaded=r.deserializeModel(r.serializeModel({b},true))[1]
assert(P.read(loaded).Floors==24);near(loaded.BuildingOrigin.CFrame.Position,moved.Position)
local cases={};local most=0
for _,kind in P.Kinds do for _,floors in {1,3,12,24} do
	local m=F.create({Kind=kind,Floors=floors,Width=12,Depth=10,Balconies=kind=='Apartment' or kind=='Residential'},base)
	local parts=0
	for _,p in m:GetDescendants() do if p:IsA('BasePart') then
		parts+=1;assert(p.Anchored and p.Size.X>0 and p.Size.Y>0 and p.Size.Z>0)
		assert(p.Size.X<200 and p.Size.Y<30 and p.Size.Z<200)
	end end
	most=math.max(most,parts);assert(parts<10000)
	assert(#m.Geometry:GetChildren()>floors and m.Geometry:FindFirstChild('Floor_'..floors))
	table.insert(cases,{Kind=kind,Floors=floors,Parts=parts})
end end
-- For every upper pane, test its centre is not buried in masonry.
local m=F.create({Floors=3,Width=12,Depth=10},C.new())
for _,floor in m.Geometry:GetChildren() do if floor.Name:match('^Floor_') then
	for _,pane in floor:GetChildren() do if pane.Name=='WindowGlass' then
		for _,wall in floor:GetChildren() do if table.find({'MasonryPier','WindowApron','WindowLintel'},wall.Name) then
			local p=wall.CFrame:PointToObjectSpace(pane.CFrame.Position);local size=wall.Size*.5
			assert(not (math.abs(p.X)<size.X-.001 and math.abs(p.Y)<size.Y-.001 and math.abs(p.Z)<size.Z-.001),'Window centre buried in wall')
		end end
	end end
end end
fs.writeFile('dist/building-geometry-validation.json',serde.encode('json',{Cases=cases,MaxParts=most,RootAndUserAdditionsPreserved=true,InvalidInputAtomic=true,RecipeRoundTrip=true,WindowsHaveRealOpenings=true,StudioPlaytestPerformed=false},true))
print('PASS: 28 building variants, 1–24 floors, real openings, signs, dimensions, moved origin, recipes, user additions and invalid input.')
