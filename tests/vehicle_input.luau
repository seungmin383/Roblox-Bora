-- Execute the actual client callbacks with UI/network adapters; no Studio.
local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local function event()
	local e={Callbacks={}}
	function e:Connect(fn) table.insert(self.Callbacks,fn) end
	function e:fire(...) for _,fn in self.Callbacks do fn(...) end end
	return e
end
local time=0;local packets={};local actions={};local render
local remote={OnClientEvent=event()}
function remote:FireServer(action,car,data) table.insert(packets,{Action=action,Data=data,Time=time}) end
local player={PlayerGui=r.Instance.new('Folder'),CharacterRemoving=event(),CameraMinZoomDistance=8,CameraMaxZoomDistance=35,CameraMode=r.Enum.CameraMode.Classic}
function player:WaitForChild() return self.PlayerGui end
local cas={}
function cas:BindActionAtPriority(name,fn) actions[name]=fn end
function cas:UnbindAction(name) actions[name]=nil end
function cas:SetTitle() end
function cas:SetPosition() end
local uis={WindowFocusReleased=event(),MouseBehavior=r.Enum.MouseBehavior.Default,MouseIconEnabled=true}
local run={BindToRenderStep=function(_,_,_,fn) render=fn end}
local camera={FieldOfView=72}
local env=setmetatable({
	game={GetService=function(_,name) return ({Players={LocalPlayer=player},ContextActionService=cas,UserInputService=uis,RunService=run,ReplicatedStorage={WaitForChild=function() return remote end}})[name] end},
	workspace={CurrentCamera=camera},Instance=r.Instance,Enum=r.Enum,UDim2=r.UDim2,UDim=r.UDim,Color3=r.Color3,
},{__index=getfenv()})
local chunk=compiler.load(fs.readFile('src/VehicleClient.client.luau'));setfenv(chunk,env);chunk()
local car=r.Instance.new('Model');car.Parent=r.Instance.new('Folder');car:SetAttribute('SpeedKmh',0)
remote.OnClientEvent:fire('State',car,'Driving')
local function tick(dt) time+=dt;render(dt) end
tick(1/240)
assert(#packets==1 and packets[1].Data.Throttle==0,'No initial neutral control packet')
local maxDelay=0
local function expectChange(trigger,check)
	local count=#packets;local start=time;trigger()
	for _=1,5 do
		tick(1/240)
		if #packets>count then break end
	end
	local delay=time-start;maxDelay=math.max(maxDelay,delay)
	assert(#packets>count and delay<=1/60+1/240+1e-8,'Input change waited for the old 100ms timer')
	assert(check(packets[#packets].Data),'Incorrect press/release control packet')
end
expectChange(function() actions.BoraVehicleLeft('BoraVehicleLeft',r.Enum.UserInputState.Begin) end,function(d) return d.Steer==-1 end)
expectChange(function() actions.BoraVehicleLeft('BoraVehicleLeft',r.Enum.UserInputState.End) end,function(d) return d.Steer==0 end)
expectChange(function() actions.BoraVehicleForward('BoraVehicleForward',r.Enum.UserInputState.Begin) end,function(d) return d.Throttle==1 end)
expectChange(function() actions.BoraVehicleBrake('BoraVehicleBrake',r.Enum.UserInputState.Begin) end,function(d) return d.Brake end)
expectChange(function() uis.WindowFocusReleased:fire() end,function(d) return d.Throttle==0 and d.Steer==0 and not d.Brake end)
expectChange(function() actions.BoraVehicleRight('BoraVehicleRight',r.Enum.UserInputState.Begin) end,function(d) return d.Steer==1 end)
expectChange(function() actions.BoraVehicleRight('BoraVehicleRight',r.Enum.UserInputState.Cancel) end,function(d) return d.Steer==0 end)
local count=#packets
for _=1,240 do tick(1/240) end
assert(#packets-count>=18 and #packets-count<=21,'Held controls are not kept alive at bounded frequency')
print('PASS: actual client key press/release, brake, focus-loss, cancel and keepalive callbacks; worst sampled input wait '..math.floor(maxDelay*1000+.5)..'ms (network delay excluded).')
