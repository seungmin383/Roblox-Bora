-- Exercise actual arcade movement; the adapter supplies geometry queries only.
local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
local V,C=r.Vector3,r.CFrame
local D=require('../src/VehicleDynamics')
local P=require('../src/VehiclePhysics')(r,D)
local catalog=serde.decode('json',fs.readFile('assets/vehicles/local/manifest.json'))
local template=require('../src/VehicleFactory')(r,catalog).create(C.new())
local function make(options)
	options=options or {};local car=template:Clone();local attrs={}
	local root={CFrame=C.new(0,D.RideHeight,0),Anchored=false,AssemblyLinearVelocity=V.new(9,8,7),AssemblyAngularVelocity=V.new(2,3,4),
		ApplyImpulseAtPosition=function() error('Suspension/traction impulses must not move this car') end}
	local world={}
	function world:Raycast(origin,direction)
		if options.Void and origin.Z<options.Void then return nil end
		if options.CenterOnly and math.abs(origin.X)>.001 then return nil end
		local y=if options.Slope then options.Slope*origin.Z else 0
		if options.Seams then y+=math.sin(origin.Z*17)*.00001 end
		if origin.Y<y or origin.Y+direction.Y>y then return nil end
		return {Position=V.new(origin.X,y,origin.Z),Normal=V.new(0,1,-(options.Slope or 0)).Unit}
	end
	function world:Blockcast(frame,size,delta)
		if options.Wall and delta.Z<0 then
			local front=(frame*C.new(0,0,-size.Z*.5)).Z
			local t=(options.Wall-front)/delta.Z
			if t>=0 and t<=1 then return {Distance=delta.Magnitude*t,Normal=V.zAxis} end
		end
		return nil
	end
	local p=P.new({Chassis=root,Mechanics=car.Mechanics,SetAttribute=function(_,k,v) attrs[k]=v end},world,{})
	local s={Car=car,Root=root,Physics=p,Attributes=attrs}
	function s:run(seconds,input,hz)
		hz=hz or 120
		for _=1,math.floor(seconds*hz) do self.Physics:step(1/hz,input) end
		return self
	end
	function s:checkWheels(slope)
		local normal=V.new(0,1,-(slope or 0)).Unit
		for _,code in {'FL','FR','RL','RR'} do
			local joint=self.Car.Mechanics['Wheel'..code]
			assert((joint.C0.Position-joint:GetAttribute('ClosedC0').Position).Magnitude<1e-5,'Wheel stretches independently of the chassis')
			local center=self.Root.CFrame:PointToWorldSpace(joint.C0.Position)
			local clearance=center:Dot(normal)-D.Radius
			assert(math.abs(clearance)<.006*D.Scale,'Wheel does not sit on the ground plane')
		end
	end
	return s
end
local drive={Throttle=1,Steer=0,Brake=false}
local coast={Throttle=0,Steer=0,Brake=false}
local brake={Throttle=0,Steer=0,Brake=true}
local flat=make():run(5,drive)
flat:checkWheels()
assert(flat.Root.Anchored and flat.Root.AssemblyAngularVelocity==V.zero and flat.Root.AssemblyLinearVelocity==V.zero,'Free-body motion was reintroduced')
assert(math.abs(flat.Root.CFrame.Y-D.RideHeight)<1e-5 and flat.Root.CFrame.LookVector.Y==0,'Flat road bounces or tilts')
local before=flat.Root.CFrame.Position
flat:run(4,brake)
assert(math.abs(flat.Physics.Speed)<.001,'Brakes do not stop')
local stopped=flat.Root.CFrame
flat:run(2,brake)
assert((flat.Root.CFrame.Position-stopped.Position).Magnitude<.001,'Stopped car creeps or oscillates')
for _,slope in {-.20,.20} do
	local s=make({Slope=slope}):run(3,drive)
	s:checkWheels(slope)
	assert(s.Root.CFrame.UpVector:Dot(V.new(0,1,-slope).Unit)>.9999,'Road grade is not followed')
end
local centerOnly=make({CenterOnly=true}):run(1,drive)
assert(centerOnly.Root.CFrame.Z< -2,'Movement still requires all four independent tire contacts')
local seams=make({Seams=true});local low,high=math.huge,-math.huge
for _=1,600 do
	seams.Physics:step(1/120,drive);low=math.min(low,seams.Root.CFrame.Y);high=math.max(high,seams.Root.CFrame.Y)
end
assert(high-low<.001,'Tiny pavement seams produce visible shaking')
local wall=-12*D.Scale
local blocked=make({Wall=wall}):run(8,drive)
local front=blocked.Root.CFrame.Z-2.325*D.Scale
assert(front>=wall+.04*D.Scale and front<wall+.10*D.Scale,'Car penetrates a wall or stops far away')
assert(blocked.Physics.Speed==0,'Blocked car continues to accelerate')
local blockedSpin=blocked.Physics.Spin
blocked:run(1,drive)
assert(math.abs(blocked.Physics.Spin-blockedSpin)<.001,'Blocked wheels keep pretending to advance')
local edge=make({Void=-8*D.Scale}):run(7,drive)
assert(edge.Root.CFrame.Z> -9*D.Scale and edge.Physics.Speed==0,'Car flies over missing ground')
local stationary=make():run(2,{Throttle=0,Steer=-1,Brake=false})
assert(stationary.Physics.Yaw==0 and stationary.Root.CFrame.Position.Magnitude<D.RideHeight+.001,'Steering spins the body while parked')
local reverse=make():run(2,{Throttle=-1,Steer=0,Brake=false})
assert(reverse.Root.CFrame.Z>0 and reverse.Physics.Speed<0,'Reverse does not move backward')
local rates={}
for _,hz in {30,60,120} do
	local s=make():run(4,drive,hz);table.insert(rates,s.Root.CFrame.Z/D.Scale)
end
assert(math.max(table.unpack(rates))-math.min(table.unpack(rates))<.5,'Movement depends excessively on frame rate')
fs.writeFile('dist/vehicle-arcade-validation.json',serde.encode('json',{
	Mode='Actual controller with deterministic plane/wall queries; Studio Play pending',
	FixedWheelMounts=true,FourWheelsOnPlane=true,NoSpringForces=true,FlatHeightStable=true,NoIdleCreep=true,
	RoadSlopes={-.2,.2},CenterSupportCanDrive=true,WallBlocksMovement=true,NoForwardMotionIntoVoid=true,
	SeamHeightVariation=high-low,FrameRates={30,60,120},PositionsMeters=rates},true))
print('PASS: stable height, four fixed wheel mounts on road/slope, no spring impulses, partial support, wall/void stops, braking/idle, reverse and 30/60/120Hz.')
