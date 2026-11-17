-- The only Place is Ro.rbxlx. Build the toolkit, then update its owned sources
-- in that existing project without rebuilding or resetting the user's world.
local fs,r,compiler,process=require('@lune/fs'),require('@lune/roblox'),require('@lune/luau'),require('@lune/process')
assert(fs.isFile('Ro.rbxlx'),'Open/save the single project as Ro.rbxlx first; this build never creates another Place.')
if table.find(process.args,'--rocket-stage') or table.find(process.args,'--rocket') then
	local work=assert(process.env.BORA_BUILDINGS_WORK,'Set BORA_BUILDINGS_WORK to a task folder in 99_Code_Work')
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local function run(mode)
		local result=process.exec(python,{'-B','tools/update_rocket.py',mode,work})
		if result.stdout~='' then print(result.stdout) end
		assert(result.ok,result.stderr)
	end
	if table.find(process.args,'--rocket-stage') then
		run('check')
		local server=r.Instance.new('Script');server.Name='BoraRocketRuntime';server.Disabled=false
		server.Source=fs.readFile('src/RocketRuntime.server.luau');compiler.compile(server.Source)
		for _,name in {'BuildingFracture','BuildingDestruction','RocketFlight','RocketLauncherFactory','RocketLauncherClient'} do
			local client=name=='RocketLauncherClient'
			local code=r.Instance.new(if client then 'LocalScript' else 'ModuleScript');code.Name=name
			code.Source=fs.readFile('src/'..name..(if client then '.client.luau' else '.luau'));compiler.compile(code.Source)
			code.Parent=server
		end
		fs.writeFile(work..'/BoraRocketRuntime.rbxmx',r.serializeModel({server},true))
		run('seal')
	else run('apply') end
	return
end
if table.find(process.args,'--building-fracture-stage') or table.find(process.args,'--building-fracture') then
	local work=assert(process.env.BORA_BUILDINGS_WORK,'Set BORA_BUILDINGS_WORK to a task folder in 99_Code_Work')
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local function run(mode)
		local result=process.exec(python,{'-B','tools/update_building_fracture.py',mode,work})
		if result.stdout~='' then print(result.stdout) end
		assert(result.ok,result.stderr)
	end
	if table.find(process.args,'--building-fracture-stage') then
		run('check')
		local demo=r.Instance.new('Script');demo.Name='BoraBuildingFractureDemo';demo.Disabled=false
		local module=r.Instance.new('ModuleScript');module.Name='BuildingFracture';module.Parent=demo
		for item,path in {[demo]='src/BuildingFractureDemo.server.luau',[module]='src/BuildingFracture.luau'} do
			item.Source=fs.readFile(path);compiler.compile(item.Source)
		end
		fs.writeFile(work..'/BoraBuildingFractureDemo.rbxmx',r.serializeModel({demo},true))
		run('seal')
	else run('apply') end
	return
end
local editorWork=nil
if table.find(process.args,'--editor-kits') or table.find(process.args,'--editor-kits-apply') then
	editorWork=assert(process.env.BORA_BUILDINGS_WORK,'Set BORA_BUILDINGS_WORK to a task folder in 99_Code_Work')
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local apply=table.find(process.args,'--editor-kits-apply')~=nil
	local result=process.exec(python,{'-B','tools/update_buildings.py',if apply then '--editor-kits-only' else '--check-kit-work',editorWork})
	if result.stdout~='' then print(result.stdout) end
	assert(result.ok,result.stderr)
	if apply then return end
end
if table.find(process.args,'--buildings-kit') or table.find(process.args,'--buildings-kit-apply') then
	local work=assert(process.env.BORA_BUILDINGS_WORK,'Set BORA_BUILDINGS_WORK to a task folder in 99_Code_Work')
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local function run(mode)
		local result=process.exec(python,{'-B','tools/update_buildings.py',mode,work})
		if result.stdout~='' then print(result.stdout) end
		assert(result.ok,result.stderr)
	end
	if table.find(process.args,'--buildings-kit-apply') then run('--kit-only')
	else run('--check-kit-work');require('./build_buildings')(work..'/BoraBuildingKit.rbxmx') end
	return
end
if table.find(process.args,'--villa-stage') or table.find(process.args,'--villa') then
	local work=assert(process.env.BORA_VILLA_WORK,'Set BORA_VILLA_WORK to the villa folder in 99_Code_Work')
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local function run(mode)
		local result=process.exec(python,{'-B','tools/update_villa.py',work,mode})
		if result.stdout~='' then print(result.stdout) end
		assert(result.ok,result.stderr)
	end
	if table.find(process.args,'--villa-stage') then
		run('capture')
		require('./build_villa')(work)
		require('./build_buildings')(work..'/BoraBuildingKit.rbxmx')
		run('seal')
	else run('apply') end
	return
end
if table.find(process.args,'--buildings-stage') or table.find(process.args,'--buildings') then
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local function run(args) local result=process.exec(python,args);if result.stdout~='' then print(result.stdout) end;assert(result.ok,result.stderr) end
	if table.find(process.args,'--buildings-stage') then
		run({'tools/update_buildings.py','--capture'});require('./build_buildings')();run({'tools/update_buildings.py','--seal'})
	else run({'tools/update_buildings.py'}) end
	return
end
if table.find(process.args,'--neighborhood-stage') or table.find(process.args,'--neighborhood') then
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local function run(args)
		local result=process.exec(python,args)
		if result.stdout~='' then print(result.stdout) end
		assert(result.ok,result.stderr)
	end
	if table.find(process.args,'--neighborhood-stage') then
		run({'tools/update_neighborhood.py','--capture'})
		compiler.compile(fs.readFile('src/NeighborhoodFactory.luau'))
		require('./build_neighborhood')()
		run({'tools/update_neighborhood.py','--seal'})
	else run({'tools/update_neighborhood.py'}) end
	return
end
local kit=r.Instance.new('Model'); kit.Name='BoraTreeKit'; kit:SetAttribute('Version','0.4.3')
local function source(class,name,path,parent)
	local text=fs.readFile(path)
	assert(type(compiler.compile(text))=='string','Compilation failed: '..name)
	local item=r.Instance.new(class); item.Name,item.Source,item.Parent=name,text,parent or kit
	return item
end
for _,name in {'TreeAssetCatalog','GrowthMath','GrowthTreeFactory','TreeParameters','TreeSkeleton','TreeMesher','TreeMeshBackend','ProceduralTreeFactory','DockPointer'} do
	source('ModuleScript',name,'src/'..name..'.luau')
end
source('Script','TreePlugin','src/ParametricTreePlugin.server.luau')
source('Script','RuntimeTemplate','src/ProceduralRuntime.server.luau').Disabled=true
local kitDir=editorWork or 'dist'
fs.writeFile(kitDir..'/BoraTreeKit.rbxmx',r.serializeModel({kit},true))
local roadKit=r.Instance.new('Model'); roadKit.Name='BoraRoadKit'; roadKit:SetAttribute('Version','0.7.1')
for _,name in {'RoadPath','RoadNetworkFactory','RoadJunctions','RoadNetwork','RoadTraffic','TrafficAssetLayout','LaneDirections','TrafficTiming','MapGuideFactory','DockPointer'} do source('ModuleScript',name,'src/'..name..'.luau',roadKit) end
source('Script','RoadPlugin','src/RoadEditorPlugin.server.luau',roadKit)
source('Script','RoadGuideRuntime','src/RoadGuideRuntime.server.luau',roadKit).Disabled=true
local trafficRuntime=source('Script','RoadTrafficRuntime','src/RoadTrafficRuntime.server.luau',roadKit); trafficRuntime.Disabled=true
source('ModuleScript','TrafficTiming','src/TrafficTiming.luau',trafficRuntime)
fs.writeFile(kitDir..'/BoraRoadKit.rbxmx',r.serializeModel({roadKit},true))
if editorWork then
	require('./build_buildings')(editorWork..'/BoraBuildingKit.rbxmx')
	local python=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
	local result=process.exec(python,{'-B','tools/update_buildings.py','--normalize-editor-kits',editorWork})
	assert(result.ok,result.stderr);print('Staged three editor kits; Place unchanged.');return
end
local map=require('../src/MapGuideFactory')(r).create()
fs.writeFile('dist/BoraRoadReference.rbxmx',r.serializeModel({map},true))
require('./build_vehicle')()
local bundled=(process.env.USERPROFILE or '')..'/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
local python=if fs.isFile(bundled) then bundled else 'python'
local extension=process.exec(python,{'tools/prepare_signal_extension.py'})
assert(extension.ok,extension.stderr)
if extension.stdout~='' then print(extension.stdout) end
local encoding=process.exec(python,{'tools/text_encoding.py'})
assert(encoding.ok,encoding.stderr)
if encoding.stdout~='' then print(encoding.stdout) end
-- Package/compile without touching an open Studio project.
if table.find(process.args,'--kits-only') then
	print('Built toolkits only; Ro.rbxlx was not modified.')
	return
end
local updateArgs={'tools/update_project.py'}
if table.find(process.args,'--vehicle-code-only') then table.insert(updateArgs,'--vehicle-code-only') end
local result=process.exec(python,updateArgs)
if result.stdout~='' then print(result.stdout) end
assert(result.ok,result.stderr)
print('Built toolkit and updated only Ro.rbxlx. Existing world layout preserved.')
