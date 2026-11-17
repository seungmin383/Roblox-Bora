local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local function event() local e={Callbacks={}};function e:Connect(fn) table.insert(self.Callbacks,fn) end;function e:fire(...) for _,fn in self.Callbacks do fn(...) end end;return e end
local objects={};local function gui(class)
	local o={ClassName=class,MouseButton1Click=event()};function o:IsA(c) return self.ClassName==c end
	function o:GetChildren() local children={};for _,p in objects do if p.Parent==self and not p.Destroyed then table.insert(children,p) end end;return children end
	function o:Destroy() self.Destroyed=true end;table.insert(objects,o);return o
end
local packets={};local remote={OnClientEvent=event()};function remote:FireServer(...) table.insert(packets,{...}) end
local root={Position=r.Vector3.new(0,3,0)};local cab={Position=r.Vector3.zero}
local model={Parent=true,IsDescendantOf=function() return true end,FindFirstChild=function() return {FindFirstChild=function() return cab end} end}
local player={Character={FindFirstChild=function() return root end},CharacterRemoving=event(),WaitForChild=function() return {} end}
local input={InputBegan=event()};local run={Heartbeat=event()}
local env=setmetatable({game={GetService=function(_,n) return ({Players={LocalPlayer=player},UserInputService=input,RunService=run,ReplicatedStorage={WaitForChild=function() return remote end}})[n] end},workspace={},
	Instance={new=gui},UDim2=r.UDim2,Vector2=r.Vector2,Color3=r.Color3,Enum=r.Enum,
},{__index=getfenv()})
local fn=compiler.load(fs.readFile('src/BuildingClient.client.luau'));setfenv(fn,env);fn()
local screen;for _,o in objects do if o.Name=='BoraElevatorFloors' then screen=o end end
assert(screen and not screen.Enabled)
remote.OnClientEvent:fire('Open',model,3,1);assert(screen.Enabled)
local button;for _,o in objects do if o.ClassName=='TextButton' and o.Text=='3층' and not o.Destroyed then button=o end end
assert(button);button.MouseButton1Click:fire();assert(#packets==1 and packets[1][1]==model and packets[1][2]==3 and not screen.Enabled)
remote.OnClientEvent:fire('Open',model,3,3);input.InputBegan:fire({KeyCode=r.Enum.KeyCode.Escape});assert(not screen.Enabled)
remote.OnClientEvent:fire('Open',model,3,1);root.Position=r.Vector3.new(100,0,0);run.Heartbeat:fire();assert(not screen.Enabled)
remote.OnClientEvent:fire('Open',model,3,1);player.CharacterRemoving:fire();assert(not screen.Enabled)
print('PASS: actual elevator client floor menu, selected floor request, Escape, leaving cab and respawn cleanup.')
