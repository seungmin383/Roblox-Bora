-- Invoked by the single build entry; emits models/scripts, never a Place.
return function()
	local r,fs,serde,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde'),require('@lune/luau')
	local catalog=serde.decode('json',fs.readFile('assets/vehicles/local/manifest.json'))
	local kit=r.Instance.new('Model');kit.Name='BoraVehicleKit';kit:SetAttribute('Version','0.1.0')
	local function source(class,name,path,parent)
		local text=fs.readFile(path);assert(type(compiler.compile(text))=='string','Vehicle compilation failed: '..path)
		local item=r.Instance.new(class);item.Name,item.Source,item.Parent=name,text,parent or kit;return item
	end
	source('ModuleScript','VehicleFactory','src/VehicleFactory.luau')
	source('ModuleScript','VehicleDynamics','src/VehicleDynamics.luau')
	source('ModuleScript','VehiclePhysics','src/VehiclePhysics.luau')
	local server=source('Script','ServerTemplate','src/VehicleRuntime.server.luau');server.Disabled=true
	for _,name in {'VehicleDynamics','VehiclePhysics'} do source('ModuleScript',name,'src/'..name..'.luau',server) end
	source('LocalScript','ClientTemplate','src/VehicleClient.client.luau').Disabled=true
	fs.writeFile('dist/BoraVehicleKit.rbxmx',r.serializeModel({kit},true))
	local car=require('../src/VehicleFactory')(r,catalog).create(r.CFrame.new(20,.08,16))
	fs.writeFile('dist/BoraSedan.rbxmx',r.serializeModel({car},true))
	print('Built vehicle scripts/model: '..catalog.TotalTriangles..' visual triangles. Place unchanged.')
end
