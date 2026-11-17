local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local C,V,E=r.CFrame,r.Vector3,r.Enum
local function event()
	local handlers={}
	return {Connect=function(_,fn) table.insert(handlers,fn) end,Once=function(_,fn) table.insert(handlers,fn) end,
		Fire=function(_,...) for _,fn in table.clone(handlers) do fn(...) end end}
end
local instances={}
local function make(class)
	local o={ClassName=class,Destroying=event(),Triggered=event(),OnServerEvent=event(),Attributes={}}
	function o:IsA(c) return self.ClassName==c or (self.ClassName=='Part' and c=='BasePart') end
	function o:SetAttribute(k,v) self.Attributes[k]=v end
	function o:GetAttribute(k) return self.Attributes[k] end
	function o:FindFirstChild(n) for _,i in instances do if i.Parent==self and i.Name==n then return i end end end
	function o:FindFirstChildOfClass(n) for _,i in instances do if i.Parent==self and i.ClassName==n then return i end end end
	function o:Destroy() self.Parent=nil;self.Destroying:Fire() end
	function o:Clone() local clone=make(self.ClassName);clone.Name=self.Name;return clone end
	table.insert(instances,o);return o
end
local workspace=make('Workspace')
local spawn=make('Part');spawn.Name='CenterSpawn';spawn.CFrame=C.new(0,.5,0);spawn.Parent=workspace
local building=make('Model');building.Parent=workspace;building:SetAttribute('AssetKind','BoraBuilding')
local surface=make('Part');surface.Parent=building
local interiorShot=false
local closeSurface=make('Part');closeSurface.Parent=building
function workspace:Raycast(origin,delta)
	if delta.Y< -15 and math.abs(delta.Z)<.001 then return {Position=V.zero,Normal=V.yAxis} end
	if interiorShot and (delta.X>.75 or (origin.Z>=-2 and origin.Z+delta.Z<=-2)) then
		assert(delta.X<.01,'The muzzle sweep hit a different nearby wall beside the avatar')
		return {Position=V.new(0,3.65,-2),Instance=closeSurface}
	end
	if origin.Z>-31 and origin.Z+delta.Z<=-31 then return {Position=V.new(0,4,-31),Instance=surface} end
	return nil
end
function workspace:GetPartBoundsInRadius() return {surface,surface} end
local replicated=make('ReplicatedStorage')
local players={PlayerRemoving=event()}
local run={IsStudio=function() return false end,Heartbeat=event()}
local debris={AddItem=function() end}
local script={RocketLauncherClient=make('LocalScript'),BuildingDestruction='Damage',BuildingFracture='Fracture',RocketFlight='Flight',RocketLauncherFactory='Model'}
script.RocketLauncherClient.Name='RocketLauncherClient'
local now=0
local frameCount,blasts=0,0
local dependencies={
	Fracture=function() return {} end,
	Damage=function()
		return {BlastRadius=11,blast=function(b,point,part)
			assert(b==building and (if interiorShot then point.Z==-2 and part==closeSurface else point.Z==-31 and part==surface));blasts+=1
		end}
	end,
	Flight=require('../src/RocketFlight'),
	Model=function()
		return {model=function(parent,frame)
			local grip=make('Part');grip.Name,grip.CFrame,grip.Parent='Handle',frame,parent
			local muzzle=make('Attachment');muzzle.Name,muzzle.WorldPosition,muzzle.Parent='Muzzle',V.new(0,4,-3),grip
			return grip
		end,rocket=function(parent,frame) frameCount+=1;local p=make('Part');p.Parent,p.CFrame=parent,frame;return p end}
	end,
}
local env=setmetatable({game={GetService=function(_,name) return ({Players=players,ReplicatedStorage=replicated,RunService=run,Debris=debris})[name] end},
	script=script,workspace=workspace,Instance={new=make},require=function(name) return assert(dependencies[name]) end,
	Enum=E,Vector3=V,CFrame=C,Color3=r.Color3,ColorSequence=r.ColorSequence,NumberSequence=r.NumberSequence,
	RaycastParams={new=function() return {} end},OverlapParams={new=function() return {} end},
	task={delay=function(_,fn) fn() end},os={clock=function() return now end}},{__index=getfenv()})
local chunk=compiler.load(fs.readFile('src/RocketRuntime.server.luau'));setfenv(chunk,env);chunk()
local function byName(n) for _,i in instances do if i.Name==n and i.Parent then return i end end end
local player=make('Player')
local char=make('Model');char.Parent=workspace;player.Character=char
local back=make('Backpack');back.Parent=player
local root=make('Part');root.Name,root.CFrame,root.Parent='HumanoidRootPart',C.new(999,3,0),char
local h=make('Humanoid');h.Died=event();h.Health,h.Parent=100,char
function h:EquipTool(tool) assert(tool.Parent==back);tool.Parent=char end
local prompt=assert(byName('PickupLauncher'));assert(prompt.KeyboardKeyCode==E.KeyCode.G)
prompt.Triggered:Fire(player);assert(not char:FindFirstChildOfClass('Tool'),'Distant player picked up the launcher')
root.CFrame=C.new(0,3,0);prompt.Triggered:Fire(player)
local tool=assert(char:FindFirstChildOfClass('Tool'));assert(tool:FindFirstChild('RocketLauncherClient'))
local remote=assert(byName('BoraRocketFire'))
remote.OnServerEvent:Fire(make('Player'),V.new(0,4,-50));assert(frameCount==0)
remote.OnServerEvent:Fire(player,'bad');assert(frameCount==0)
remote.OnServerEvent:Fire(player,V.new(0,4,-50));assert(frameCount==1)
remote.OnServerEvent:Fire(player,V.new(0,4,-50));assert(frameCount==1 and blasts==0)
for _=1,20 do run.Heartbeat:Fire(1/60) end
assert(blasts==1 and byName('RocketBlast').BlastPressure==0)
now=2
tool.Parent=back;remote.OnServerEvent:Fire(player,V.new(0,4,-50));assert(frameCount==1)
tool.Parent=char;interiorShot=true
tool:FindFirstChild('Handle'):FindFirstChild('Muzzle').WorldPosition=V.new(3,3.65,-3)
remote.OnServerEvent:Fire(player,V.new(0,3.65,-2))
if blasts==1 then for _=1,4 do run.Heartbeat:Fire(1/60) end end
assert(blasts==2,'Close-range shot did not damage the wall in the sightline')
players.PlayerRemoving:Fire(player);assert(byName('PickupLauncher'))
local input=make('Tool');input.Activated=event();input.Parent=char
local clickCount=0
local mouse={Hit=C.new(0,4,-50)}
function player:GetMouse() return mouse end
local clientRemote={FireServer=function(_,aim) assert(aim==mouse.Hit.Position);clickCount+=1 end}
local clientEnv=setmetatable({script={Parent=input},os={clock=function() return now end},game={GetService=function(_,service)
	return if service=='Players' then {LocalPlayer=player} else {WaitForChild=function() return clientRemote end}
end}},{__index=getfenv()})
local client=compiler.load(fs.readFile('src/RocketLauncherClient.client.luau'));setfenv(client,clientEnv);client()
input.Activated:Fire();input.Activated:Fire();assert(clickCount==1)
input.Parent=back;now+=2;input.Activated:Fire();assert(clickCount==1)
print('PASS: G pickup, client click aim, equip/distance/cooldown validation, first-surface impact, close interior shot and pickup return.')
