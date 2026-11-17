-- Stage only approved vehicle pose deltas. The Place is never written here.
local r,fs,serde,process=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde'),require('@lune/process')
local wrapper=r.deserializeModel(fs.readFile('dist/VehicleLayoutInput.rbxmx'))[1]
local car=wrapper.Existing;local plan=serde.decode('json',wrapper.Plan.Value)
local scale=1/.28;local root=car.Chassis
local function delta(a,b) return (r.Vector3.new(table.unpack(a))-r.Vector3.new(table.unpack(b)))*scale end
for name,pivot in plan.New.Pivots do
	local previous=plan.Old.Pivots[name];assert(previous,'Unknown old vehicle pivot '..name)
	local shift=delta(pivot,previous)
	local hub=car.Components[name].Pivot;local motor=car.Mechanics[name]
	hub.CFrame=root.CFrame*r.CFrame.new(shift)*root.CFrame:ToObjectSpace(hub.CFrame)
	motor.C0=r.CFrame.new(shift)*motor.C0
	motor:SetAttribute('ClosedC0',r.CFrame.new(shift)*motor:GetAttribute('ClosedC0'))
end
local legacyZero=true
for name in plan.Old.Markers do if root[name].CFrame.Position.Magnitude>1e-5 then legacyZero=false end end
for name,position in plan.New.Markers do
	local marker=root:FindFirstChild(name);assert(marker,'Missing vehicle attachment '..name)
	if legacyZero then marker.CFrame=r.CFrame.new(r.Vector3.new(table.unpack(position))*scale)*marker.CFrame.Rotation
	else marker.CFrame=r.CFrame.new(delta(position,plan.Old.Markers[name]))*marker.CFrame end
end
local shift=delta(plan.New.SeatPosition,plan.Old.SeatPosition)
car.DriverSeat.CFrame=root.CFrame*r.CFrame.new(shift)*root.CFrame:ToObjectSpace(car.DriverSeat.CFrame)
car:SetAttribute('Design',plan.Design);car:SetAttribute('Version',3);car:SetAttribute('NumericInstrumentSpeed',true)
fs.writeFile('dist/VehicleLayoutUpgrade.rbxmx',r.serializeModel({car},true))
print('Staged vehicle layout; parked frame, custom offsets and object identities retained.')
