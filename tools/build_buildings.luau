-- Package the editor and stage recipes from the saved world. Never serialize a Place.
return function(kitOutput)
	local r,fs,luau,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau'),require('@lune/serde')
	local P=require('../src/BuildingParameters');local F=require('../src/BuildingFactory')(r,P)
	local B=require('../src/BuildingPlan')({Decode=function(text) return serde.decode('json',text) end,Encode=function(value) return serde.encode('json',value) end})
	local Interior=require('../src/BuildingInteriorFactory')(r,B)
	if not kitOutput and fs.isFile('assets/buildings/local/manifest.json') then require('./build_building_decorations')() end
	local kit=r.Instance.new('Model');kit.Name='BoraBuildingKit';kit:SetAttribute('Version',F.Version)
	for _,spec in {{'ModuleScript','BuildingParameters','src/BuildingParameters.luau'},{'ModuleScript','BuildingFactory','src/BuildingFactory.luau'},
		{'ModuleScript','BuildingPlan','src/BuildingPlan.luau'},{'ModuleScript','BuildingInteriorFactory','src/BuildingInteriorFactory.luau'},{'ModuleScript','DockPointer','src/DockPointer.luau'},
		{'ModuleScript','BuildingPlanEditor','src/BuildingPlanEditor.luau'},
		{'Script','BuildingPlugin','src/BuildingEditorPlugin.server.luau'},{'Script','RuntimeTemplate','src/BuildingRuntime.server.luau'},{'LocalScript','ClientTemplate','src/BuildingClient.client.luau'}} do
		local text=fs.readFile(spec[3]);assert(type(luau.compile(text))=='string')
		local m=r.Instance.new(spec[1]);m.Name,m.Source,m.Parent=spec[2],text,kit
	end
	kit.RuntimeTemplate.Disabled=true;kit.ClientTemplate.Disabled=true
	for _,template in {kit.RuntimeTemplate,kit.ClientTemplate} do template:SetAttribute('BoraOwned',true);template:SetAttribute('BuildingVersion',F.Version) end
	for _,name in {'BuildingElevatorMotion','BuildingElevatorActor'} do
		local text=fs.readFile('src/'..name..'.luau');luau.compile(text)
		local module=r.Instance.new('ModuleScript');module.Name,module.Source,module.Parent=name,text,kit.RuntimeTemplate
	end
	if fs.isFile('dist/BuildingDecorations.rbxmx') then
		local decorations=r.deserializeModel(fs.readFile('dist/BuildingDecorations.rbxmx'))[1];decorations.Parent=kit
	end
	fs.writeFile(kitOutput or 'dist/BoraBuildingKit.rbxmx',r.serializeModel({kit},true))
	if kitOutput then return end
	local place=r.deserializePlace(fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*',''))
	local town=place:GetService('Workspace'):FindFirstChild('BoraNeighborhood_01');assert(town and town:FindFirstChild('Buildings'))
	local input=serde.decode('json',fs.readFile('dist/building-staging.json'))
	local patches=r.Instance.new('Model');patches.Name='BuildingPatches'
	local preview=r.Instance.new('Model');preview.Name='BuildingPreview'
	local function hex(c) return string.format('%02X%02X%02X',math.floor(c.R*255+.5),math.floor(c.G*255+.5),math.floor(c.B*255+.5)) end
	local decorated=require('../src/BuildingFactory')(r,P,kit:FindFirstChild('Decorations'),B,Interior)
	for _,b in town.Buildings:GetChildren() do
		if b:GetAttribute('AssetKind')=='BoraBuilding' then local m=decorated.create(P.read(b),b.BuildingOrigin.CFrame);m.Name=b.Name;m.Parent=preview;continue end
		local slab=b:FindFirstChild('GroundFloorSlab');local wall=b:FindFirstChild('UpperMasonry');local board=b:FindFirstChild('ShopSign')
		assert(slab and wall and board,'Unknown legacy building; preserve it: '..b.Name)
		local base=slab.CFrame*r.CFrame.new(0,.08/.28,0)
		local p=P.normalize({Kind=b:GetAttribute('BuildingUse'),Floors=b:GetAttribute('Floors'),Title=input.titles[b.Name],
			Width=slab.Size.X*.28-.2,Depth=slab.Size.Z*.28-.2,Apron=b.Forecourt.Size.Z*.28,
			Wall=hex(wall.Color),Trim=hex(b.RoofCap.Color),Accent=hex(board.Color),Balconies=b:GetAttribute('BuildingUse')=='Residential'})
		local m=decorated.create(p,base);m.Name=b.Name
		for key,value in b:GetAttributes() do if m:GetAttribute(key)==nil then m:SetAttribute(key,value) end end
		m:Clone().Parent=preview;m.Parent=patches
	end
	-- A tall apartment is a model preview only; it is never inserted into the Place.
	local apartment=decorated.create({Kind='Apartment',Title='보라 아파트 101',Floors=12,Width=18,Depth=12,Balconies=true,Awning=false,Wall='D8D7CF',Trim='EEECE1',Accent='586D71'},r.CFrame.new(0,0,0))
	fs.writeFile('dist/BuildingApartmentPreview.rbxmx',r.serializeModel({apartment},true))
	local config=P.normalize({Kind='Shop',Title='도면 편집 예제',Floors=3,Width=16,Depth=12,Details=false,Awning=false})
	local layout={Version=1,Items={
		{Id=1,Kind='Wall',Floor=1,X=0,Z=-4.5,X2=0,Z2=2,Thickness=.16},
		{Id=2,Kind='Stairs',Floor=1,X=-4.5,Z=1,Rotation=0},
		{Id=3,Kind='Stairs',Floor=2,X=-4.5,Z=1,Rotation=0},
		{Id=4,Kind='Elevator',X=4.5,Z=2,Rotation=0},
		{Id=5,Kind='Block',Floor=1,X=2,Z=-1,Width=1,Depth=.5,Rotation=0},
	}}
	config.PlanJSON=B.encode(layout,config)
	local example=decorated.create(config,r.CFrame.new())
	fs.writeFile('dist/BuildingFloorPlanPreview.rbxmx',r.serializeModel({example},true))
	fs.writeFile('dist/building-floorplan-example.json',serde.encode('json',{Config=config,Plan=layout},true))
	fs.writeFile('dist/BuildingPatches.rbxmx',r.serializeModel({patches},true))
	fs.writeFile('dist/BuildingPreview.rbxmx',r.serializeModel({preview},true))
	print('Packaged building editor and staged modular models; Place unchanged.')
end
