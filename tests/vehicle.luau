local r,fs,serde,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde'),require('@lune/luau')
local D=require('../src/VehicleDynamics')
local Catalog=serde.decode('json',fs.readFile('assets/vehicles/local/manifest.json'))
for _,name in {'VehicleFactory','VehicleDynamics','VehiclePhysics','VehicleRuntime.server','VehicleClient.client'} do
	assert(type(compiler.compile(fs.readFile('src/'..name..'.luau')))=='string',name..' compilation failed')
end
local car=require('../src/VehicleFactory')(r,Catalog).create(r.CFrame.new(20,.08,16))
assert(car.PrimaryPart==car.Chassis and car.Chassis.CanCollide and not car.Chassis.Massless)
local parts=0
for _,item in car:GetDescendants() do
	if item:IsA('BasePart') then
		parts+=1;assert(not item.Anchored,'A visual part freezes the car')
		if item~=car.Chassis then assert(not item.CanCollide and item.Massless,'Visual collision/mass destabilizes the chassis') end
		if item.Name:match('^Glass_') then assert(item.Material==r.Enum.Material.Glass and item.Transparency>=.6,'Window is not actual transparent glass') end
	end
end
for _,name in {'DoorFL','DoorFR','DoorRL','DoorRR','WheelFL','WheelFR','WheelRL','WheelRR','Steering'} do
	assert(car.Components[name] and car.Mechanics[name]:IsA('Motor6D'))
	assert(car.Mechanics[name].Part0==car.Chassis and car.Mechanics[name].Part1==car.Components[name].Pivot)
end
assert(car.DriverSeat.Disabled and car.DriverSeat.Transparency==1 and car.DriverSeat:FindFirstChildOfClass('WeldConstraint'))
assert(car.Chassis.Eye.CFrame.Position.Y>car.Chassis.SeatedRoot.CFrame.Position.Y)
assert(car.Components.Steering.Pivot.LeftGrip and car.Components.Steering.Pivot.RightGrip)
local loaded=r.deserializeModel(r.serializeModel({car},true))[1]
assert(loaded.Mechanics.DoorFL.Part1==loaded.Components.DoorFL.Pivot and loaded.PrimaryPart==loaded.Chassis,'Serialization broke articulated references')
for _,bad in {false,{}, {Throttle=0/0,Steer=0,Brake=false},{Throttle=2,Steer=0,Brake=false},{Throttle=0,Steer=math.huge,Brake=false}} do assert(D.input(bad)==nil) end
assert(D.input({Throttle=1,Steer=-1,Brake=false}).Steer==-1)
assert(D.canEnter('Empty',0,true,12) and not D.canEnter('Driving',0,true,2) and not D.canEnter('Empty',0,false,2) and not D.canEnter('Empty',0,true,13))
assert(D.exitReady(1) and not D.exitReady(2))
-- Fixed step acceleration/braking/reversing and speed-sensitive steering.
local speed=0
for _=1,60*20 do local a=D.control(speed,{Throttle=1,Steer=0,Brake=false});speed+=a/60 end
assert(speed/D.Scale>29 and speed/D.Scale<=30.001,'Forward limit/acceleration')
for _=1,60*5 do local a=D.control(speed,{Throttle=0,Steer=0,Brake=true});speed+=a/60 end
assert(math.abs(speed)<.01,'Braking does not stop')
for _=1,60*15 do local a=D.control(speed,{Throttle=-1,Steer=0,Brake=false});speed+=a/60 end
assert(speed/D.Scale< -6.9 and speed/D.Scale>= -7.001,'Reverse limit')
local _,slow=D.control(0,{Throttle=0,Steer=-1,Brake=false})
local _,fast=D.control(30*D.Scale,{Throttle=0,Steer=-1,Brake=false})
assert(slow>fast and fast>0 and D.wheelAngle(slow,-.795*D.Scale)>D.wheelAngle(slow,.795*D.Scale),'Steer direction/Ackermann geometry')
-- Execute the real arcade controller with flat-ground/collision adapters.
local root=car.Chassis
local mockRoot={CFrame=root.CFrame,Anchored=true,AssemblyLinearVelocity=r.Vector3.zero,AssemblyAngularVelocity=r.Vector3.zero}
local mockCar={Chassis=mockRoot,Mechanics=car.Mechanics,SetAttribute=function() end}
local world={Raycast=function(_,origin)
    return {Position=r.Vector3.new(origin.X,.08,origin.Z),Normal=r.Vector3.yAxis}
end,Blockcast=function() return nil end}
local physics=require('../src/VehiclePhysics')(r,D).new(mockCar,world,{})
local start=mockRoot.CFrame.Position
for _=1,60 do physics:step(1/60,{Throttle=1,Steer=0,Brake=false}) end
assert(mockRoot.CFrame.Z<start.Z and math.abs(mockRoot.CFrame.X-start.X)<.001,'Arcade forward movement direction')
assert(mockRoot.Anchored and mockRoot.AssemblyAngularVelocity==r.Vector3.zero,'Car still uses free rigid-body rotation')
local joint=car.Mechanics.Steering
local closed=joint:GetAttribute('ClosedC0')
local wheelTop=r.Vector3.new(0,math.sqrt(3)/2,-.5)
local neutralTop=closed:VectorToWorldSpace(wheelTop)
for _,travel in {1,-1} do
    for _,steerInput in {-1,1} do
        mockRoot.CFrame=r.CFrame.new(0,D.RideHeight+.08,0)
        local controller=require('../src/VehiclePhysics')(r,D).new(mockCar,world,{})
        controller.Speed=travel*6*D.Scale
        for _=1,6 do controller:step(1/60,{Throttle=travel,Steer=steerInput,Brake=false}) end
        local wheelMovement=joint.C0:VectorToWorldSpace(wheelTop)-neutralTop
        assert(wheelMovement.X*steerInput>0,'Steering wheel turns opposite to A/D from the driver seat')
        assert(controller.Yaw*steerInput*travel<0,'Forward/reverse turning direction')
        for _,code in {'FL','FR','RL','RR'} do
            local wheel=car.Mechanics['Wheel'..code]
            assert((wheel.C0.Position-wheel:GetAttribute('ClosedC0').Position).Magnitude<.00001,'Wheel position stretches away from the body')
        end
    end
end
fs.writeFile('dist/vehicle-validation.json',serde.encode('json',{Parts=parts,Triangles=Catalog.TotalTriangles,IndependentDoors=4,IndependentWheels=4,Physics='ground-following arcade pose, rigid wheel mounts, acceleration/brake/reverse and steering',Mode='Automated; Studio playtest pending'},true))
print('PASS: separate pivots/welds, save/reload, cabin markers, input guards, entry/exit gates, acceleration/brake/reverse, steering, fixed wheel positions and stable arcade movement.')
