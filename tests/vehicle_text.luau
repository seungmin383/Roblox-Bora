local fs,r=require('@lune/fs'),require('@lune/roblox')
local kit=r.deserializeModel(fs.readFile('dist/BoraVehicleKit.rbxmx'))[1]
local function lf(source) return (source:gsub('\r\n','\n')) end
assert(lf(kit.ClientTemplate.Source)==lf(fs.readFile('src/VehicleClient.client.luau')))
assert(lf(kit.ServerTemplate.Source)==lf(fs.readFile('src/VehicleRuntime.server.luau')))
local car=r.deserializeModel(fs.readFile('dist/BoraSedan.rbxmx'))[1]
assert(car.Components.DoorFL.Pivot.DoorPrompt.Interact.ObjectText=='BORA 세단 · 운전석')
assert(car.Components.DoorFR.Pivot.DoorPrompt.Interact.ActionText=='문 열기 / 닫기')
assert(car.DashboardDisplay.SpeedDisplay.Gear.Text=='P' and car.CenterDisplay.Infotainment.Status.Text=='주행 준비')
print('PASS: packaged Luau sources, Korean prompts and cockpit screens retain exact UTF-8 text.')
