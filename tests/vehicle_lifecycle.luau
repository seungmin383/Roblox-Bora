-- Execute the real server entry/exit routines with deterministic tween/seat
-- adapters. Roblox physics and avatar rendering still require a Play check.
local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local D=require('../src/VehicleDynamics')
local C,V=r.CFrame,r.Vector3
local function event()
	local e={Callbacks={}}
	function e:Connect(fn) table.insert(self.Callbacks,fn);local active=true;return {Disconnect=function() active=false end} end
	function e:fire(...) for _,fn in self.Callbacks do fn(...) end end
	return e
end
local messages={};local remote={OnServerEvent=event(),FireClient=function(_,player,kind,car,state) table.insert(messages,{Player=player,Kind=kind,State=state}) end}
local emptyFolder={GetChildren=function() return {} end,ChildAdded=event()}
local players={PlayerRemoving=event()};local heartbeat=event()
local tweens=0
local tween={Create=function(_,target,info,props)
	return {Play=function() tweens+=1;for key,value in props do target[key]=value end end,Completed={Wait=function() end}}
end}
local world={WaitForChild=function() return emptyFolder end,Raycast=function(_,origin) return {Position=V.new(origin.X,0,origin.Z)} end}
local now=0
local env=setmetatable({workspace=world,script={VehicleDynamics='D',VehiclePhysics='P'},
	game={GetService=function(_,name) return ({Players=players,RunService={Heartbeat=heartbeat},TweenService=tween,ReplicatedStorage={WaitForChild=function() return remote end}})[name] end},
	require=function(name) if name=='D' then return D else return function() return {} end end end,
	task={wait=function() end,spawn=function(fn,...) fn(...) end},TweenInfo={new=function() return {} end},
	os={clock=function() return now end},Vector3=V,CFrame=C,Enum=r.Enum},{__index=getfenv()})
local source=fs.readFile('src/VehicleRuntime.server.luau')..'\nreturn {Enter=enter,Exit=exit,Cleanup=cleanup,Players=players,Sessions=sessions}\n'
local chunk=compiler.load(source);setfenv(chunk,env);local runtime=chunk()
local humanoid={Health=100,WalkSpeed=16,JumpPower=50,JumpHeight=7.2,AutoRotate=true,HipHeight=2,Parent=true,Died=event(),
	FindFirstChildOfClass=function() return nil end}
local hrp={CFrame=C.new(-4,3,0),Position=V.new(-4,3,0),Size=V.new(2,2,1),Anchored=false,CanCollide=false,Parent=true,IsA=function(_,name) return name=='BasePart' end}
local waist={Name='Waist',C0=C.new(0,1,0),Parent=true,IsA=function(_,name) return name=='Motor6D' end}
local body={CanCollide=true,Parent=true,IsA=function(_,name) return name=='BasePart' end}
local head={Position=hrp.Position+V.new(0,2,0),Size=V.new(1,1,1)}
local character={FindFirstChildOfClass=function() return humanoid end,
	FindFirstChild=function(_,name) if name=='HumanoidRootPart' then return hrp elseif name=='Head' then return head end end,
	GetDescendants=function() return {hrp,waist,body} end}
local player={Character=character,Parent=true}
local root={CFrame=C.new(0,.62*D.Scale,0),Position=V.new(0,.62*D.Scale,0),AssemblyLinearVelocity=V.zero,AssemblyAngularVelocity=V.zero,Anchored=true,
	DriverHandle={WorldPosition=V.new(-3,3,0)},OutsideDriver={CFrame=C.new(-4,1,0)},SeatedRoot={CFrame=C.new(-1,1,1)},Eye={Position=V.new(0,.58*D.Scale,0)},SetNetworkOwner=function() error('Anchored arcade car must not assign network ownership') end}
local seat={Disabled=true,Occupant=nil,Parent=true}
function seat:Sit(hum)
	self.Occupant=hum;self.SeatWeld={C0=C.new(),C1=C.new(),Destroy=function() self.SeatWeld=nil;self.Occupant=nil end}
end
function seat:WaitForChild() return self.SeatWeld end
function seat:FindFirstChild() return self.SeatWeld end
seat.CFrame=C.new(-1,1,1)
local mechanics={}
for _,name in {'DoorFL','DoorFR','DoorRL','DoorRR'} do
	local attrs={ClosedC0=C.new(),Open=false}
	mechanics[name]={GetAttribute=function(_,key) return attrs[key] end,SetAttribute=function(_,key,value) attrs[key]=value end}
end
function mechanics:FindFirstChild(name) return self[name] end
local car={Chassis=root,DriverSeat=seat,Driver={Value=nil},Mechanics=mechanics,Parent=true,
	GetDescendants=function() return {} end,SetAttribute=function() end,GetAttribute=function() return 0 end,
	FindFirstChild=function() return nil end,DashboardDisplay={SpeedDisplay={Speed={},FindFirstChild=function() return nil end}}}
local physics={Speed=0,Resets=0,step=function() end}
function physics:reset() self.Speed=0;self.Resets+=1 end
local s={Car=car,State='Empty',Token=0,IK={},Input={Throttle=0,Steer=0,Brake=true},Ray={},Physics=physics}
local originalWaist=waist.C0
runtime.Enter(s,player)
assert(s.State=='Driving' and car.Driver.Value==player and seat.Occupant==humanoid and root.Anchored)
assert(math.abs(s.AvatarEyeHeight-2.12)<.001,'Avatar eye height was measured after moving the character')
local seatedFrame=seat.CFrame*seat.SeatWeld.C0
assert(math.abs(seatedFrame.Position.Y-(root.Position.Y+root.Eye.Position.Y-s.AvatarEyeHeight))<.001,'Seated avatar eyes do not match cockpit camera height')
assert(not hrp.Anchored and not body.CanCollide and humanoid.WalkSpeed==0)
assert(mechanics.DoorFL:GetAttribute('Open')==false and waist.C0==originalWaist)
local stranger={Character=character,Parent=true}
runtime.Enter(s,stranger);assert(s.Player==player,'Second player stole an occupied driver seat')
now=1;remote.OnServerEvent:fire(stranger,'Input',car,{Throttle=1,Steer=0,Brake=false});assert(s.Input.Throttle==0)
remote.OnServerEvent:fire(player,'Input',car,{Throttle=math.huge,Steer=0,Brake=false});assert(s.Input.Throttle==0)
remote.OnServerEvent:fire(player,'Input',car,{Throttle=1,Steer=-1,Brake=false});assert(s.Input.Throttle==1 and s.Input.Steer==-1)
now+=1/60
remote.OnServerEvent:fire(player,'Input',car,{Throttle=0,Steer=0,Brake=true})
assert(s.Input.Throttle==0 and s.Input.Steer==0 and s.Input.Brake,'Server rejected a next-frame release/brake update')
remote.OnServerEvent:fire(player,'Exit',car);assert(s.ExitPending)
runtime.Sessions[car]=s
physics.Speed=10
heartbeat:fire(1/60)
assert(s.State=='Driving' and seat.Occupant==humanoid,'Zero assembly velocity caused an exit while arcade car is still moving')
physics.Speed=0
heartbeat:fire(1/60)
assert(physics.Resets>=2,'Entry/cleanup did not reset the arcade speed')
runtime.Sessions[car]=nil
assert(s.State=='Empty' and car.Driver.Value==nil and root.Anchored and seat.Disabled)
assert(not hrp.Anchored and body.CanCollide and humanoid.WalkSpeed==16 and humanoid.JumpPower==50 and humanoid.AutoRotate)
assert(waist.C0==originalWaist and runtime.Players[player]==nil)
assert(messages[1].State=='Entering' and messages[2].State=='Driving')
assert(tweens>=12,'Door/character transition tweens did not run')
-- Death during driving must release the slot and all frozen character state.
runtime.Enter(s,player);assert(s.State=='Driving')
runtime.Cleanup(s)
assert(s.State=='Empty' and not hrp.Anchored and body.CanCollide and runtime.Players[player]==nil)
print('PASS: actual server entry/door/seat/drive/exit path, duplicate drivers, invalid/foreign input guards and cleanup restores character state.')
