-- Actual server entry callbacks with deterministic transport/query adapters.
local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local Motion=require('../src/BuildingElevatorMotion');local time=0
local function event()
	local e={Callbacks={}};function e:Connect(fn) local c={Fn=fn,Live=true};table.insert(self.Callbacks,c);return {Disconnect=function() c.Live=false end} end
	function e:fire(...) for _,c in self.Callbacks do if c.Live then c.Fn(...) end end end;return e
end
local nearRoot={CFrame=r.CFrame.new(0,0,0)}
local character={Inside=false,FindFirstChild=function() return nearRoot end,FindFirstChildOfClass=function() return {Health=100} end}
local player={Character=character};local calls={};local actors={};local cleanup=0
local remote={OnServerEvent=event(),IsA=function() return true end,GetAttribute=function() return true end}
function remote:FireClient(...) table.insert(calls,{...}) end
local players={PlayerRemoving=event(),GetPlayers=function() return {player} end}
local run={Heartbeat=event()};local replicated={FindFirstChild=function() return remote end}
local model={Stops={},ShaftOrigin={},Landings={},Cab={ControlPanel={SelectFloor={Triggered=event()}}}}
for floor=1,3 do model.Landings['Floor_'..floor]={CallButton={CFrame=r.CFrame.new(0,(floor-1)*12,0),Call={Triggered=event()}}} end
function model:IsA(class) return class=='Model' end
function model:GetAttribute() return true end
function model:FindFirstChild(name) return self[name] end
local actorFactory={}
function actorFactory.new(m)
	local a={State=Motion.new({0,3.45,6.5}),Connections={},inside=function(_,char) return char.Inside end}
	function a:step(dt) if self.Fail then error('Injected controller failure') end;Motion.step(self.State,dt) end
	function a:destroy() cleanup+=1;for _,c in self.Connections do c:Disconnect() end end
	actors[m]=a;return a
end
local world={DescendantAdded=event(),DescendantRemoving=event(),GetDescendants=function() return {model} end}
local script={BuildingElevatorMotion={},BuildingElevatorActor={}}
local env=setmetatable({game={GetService=function(_,n) return ({Players=players,RunService=run,ReplicatedStorage=replicated})[n] end,BindToClose=function() end},
	workspace=world,script=script,CFrame=r.CFrame,Vector3=r.Vector3,
	require=function(m) return if m==script.BuildingElevatorMotion then Motion else function() return actorFactory end end,
	os={clock=function() return time end},task={defer=function(fn) fn() end},warn=function() end,
},{__index=getfenv()})
local fn=compiler.load(fs.readFile('src/BuildingRuntime.server.luau'));setfenv(fn,env);fn()
local a=actors[model];assert(a)
nearRoot.CFrame=r.CFrame.new(1000,0,0);model.Landings.Floor_2.CallButton.Call.Triggered:fire(player);assert(#a.State.Queue==0)
nearRoot.CFrame=model.Landings.Floor_2.CallButton.CFrame;model.Landings.Floor_2.CallButton.Call.Triggered:fire(player);assert(a.State.Queue[1]==2)
remote.OnServerEvent:fire(player,model,3);assert(#a.State.Queue==1,'Outside client selected a floor')
character.Inside=true;model.Cab.ControlPanel.SelectFloor.Triggered:fire(player);assert(#calls==1 and calls[1][2]=='Open')
remote.OnServerEvent:fire(player,model,3);assert(a.State.Queue[2]==3)
remote.OnServerEvent:fire(player,model,1);assert(#a.State.Queue==2,'Remote rate limit ignored')
time=1;remote.OnServerEvent:fire(player,{},1);assert(#a.State.Queue==2,'Unregistered lift accepted')
remote.OnServerEvent:fire(player,model,'bad');assert(#a.State.Queue==2)
a.Fail=true;run.Heartbeat:fire(1/60);assert(cleanup==1,'Controller failure did not release/disconnect actor')
model.Cab.ControlPanel.SelectFloor.Triggered:fire(player);assert(#calls==1,'Removed actor still accepts prompts')
print('PASS: actual elevator server prompts, distance checks, client presence/rate limits, registered models and controller-error cleanup.')
