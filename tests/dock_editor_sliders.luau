-- Exercise the real road/tree slider bindings with no viewport mouse release.
local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local P=require('../src/TreeParameters');local E=r.Enum;local V=r.Vector3
local dep=compiler.load(fs.readFile('src/DockPointer.luau'))
setfenv(dep,setmetatable({Enum=E},{__index=getfenv()}));local D=dep()
local function event()
	local list={}
	return {
		Connect=function(_,fn)
			local c={Fn=fn,Active=true};table.insert(list,c)
			return {Disconnect=function() c.Active=false end}
		end,
		fire=function(_,...) for _,c in table.clone(list) do if c.Active then c.Fn(...) end end end,
	}
end
local function harness(file,dependencies,world,extra)
	local nodes,toolbarButtons={},{};local point=0
	local function gui(class)
		local o={ClassName=class,Activated=event(),InputBegan=event(),InputEnded=event(),AbsolutePosition=r.Vector2.zero,AbsoluteSize=r.Vector2.new(100,16)}
		function o:GetPropertyChangedSignal() return event() end
		function o:Clone() return gui(class) end
		function o:Destroy() end
		table.insert(nodes,o);return o
	end
	local w={Enabled=false,WindowFocusReleased=event(),GetRelativeMousePosition=function() return r.Vector2.new(point,0) end,BindToClose=function() end}
	local mouse={Move=event(),Button1Down=event(),Button1Up=event()}
	local plugins={Deactivation=event(),Unloading=event()}
	function plugins:CreateToolbar()
		return {CreateButton=function(_,id) local b={Click=event()};function b:SetActive() end;toolbarButtons[id]=b;return b end}
	end
	function plugins:CreateDockWidgetPluginGuiAsync() return w end
	function plugins:GetMouse() return mouse end
	function plugins:Deactivate() end
	local hist={OnUndo=event(),OnRedo=event(),Commits=0,Cancels=0}
	function hist:TryBeginRecording() if self.Snapshot then self.Undo=self.Snapshot() end;return 'record' end
	function hist:FinishRecording(_,op)
		if op==E.FinishRecordingOperation.Commit then self.Commits+=1
		else self.Cancels+=1;if self.Undo then self.Undo() end end
	end
	local selection={SelectionChanged=event(),Items={}}
	function selection:Get() return self.Items end
	local run={Heartbeat=event(),IsRunning=function() return false end}
	local viewport={InputBegan=event(),InputEnded=event()}
	local services={RunService=run,Selection=selection,ChangeHistoryService=hist,UserInputService=viewport}
	for k,v in extra or {} do services[k]=v end
	dependencies.DockPointer=D
	local parent=setmetatable({},{__index=function(_,k) return k end})
	local env=setmetatable({plugin=plugins,script={Parent=parent},workspace=world,
		Instance={new=gui},Enum=E,Vector2=r.Vector2,Vector3=V,UDim2=r.UDim2,Color3=r.Color3,CFrame=r.CFrame,
		DockWidgetPluginGuiInfo={new=function() return {} end},task={spawn=function(fn) fn() end,defer=function() end,wait=function() end},
		game={GetService=function(_,k) return services[k] end},require=function(k) return assert(dependencies[k],k) end},{__index=getfenv()})
	local runPlugin=compiler.load(fs.readFile('src/'..file..'.server.luau'));setfenv(runPlugin,env);runPlugin()
	local function node(name,parentName)
		for _,o in nodes do if o.Name==name and (not parentName or o.Parent.Name==parentName) then return o end end
		error(name)
	end
	local function gesture(track,at)
		local changed=event()
		local press={UserInputType=E.UserInputType.MouseButton1,UserInputState=E.UserInputState.Begin,
			GetPropertyChangedSignal=function() return changed end}
		point=at;track.InputBegan:fire(press)
		return function(x,how)
			point=x
			if how=='widget' then track.InputEnded:fire(press)
			else
				press.UserInputState=if how=='cancel' then E.UserInputState.Cancel else E.UserInputState.End
				changed:fire()
			end
		end
	end
	return {node=node,button=toolbarButtons,gesture=gesture,history=hist,select=selection,window=w,viewport=viewport}
end
local function stub(value) return function() return value or {} end end
local mapAttrs={Width=1200,Rotation=0,Opacity=.9,Visible=true,Aspect=2036/3970,DisplayVersion=6,Image='rbxasset://BoraRoadKit/MapReference.png'}
local map={GetAttribute=function(_,k) return mapAttrs[k] end,SetAttribute=function(_,k,v) mapAttrs[k]=v end,
	Root={Position=V.zero,CFrame=r.CFrame.new()}}
local road=harness('RoadEditorPlugin',{
	RoadPath=stub({}),LaneDirections=stub(),RoadTraffic=stub({Defaults={}}),TrafficAssetLayout={},
	RoadNetworkFactory=stub({isRoad=function() return false end}),RoadJunctions=stub(),RoadNetwork=stub(),
	MapGuideFactory=stub({DefaultImage=mapAttrs.Image,isGuide=function(m) return m==map end,update=function(_,width) mapAttrs.Width=width end}),
},{FindFirstChild=function(_,k) if k=='BoraMapReference' then return map end end})
road.button.BoraRoadEditor.Click:fire()
local mapWidth=road.node('WidthSlider','MapControls')
local release=road.gesture(mapWidth,35)
road.viewport.InputEnded:fire({UserInputType=E.UserInputType.MouseButton1})
assert(mapAttrs.Width==1200 and road.history.Commits==0)
release(50,'widget');assert(mapAttrs.Width==8050 and road.history.Commits==1)
release=road.gesture(mapWidth,20);release(90,'cancel');assert(mapAttrs.Width==8050 and road.history.Commits==1)
local model=r.Instance.new('Model');model.Parent=r.Instance.new('Folder');model:SetAttribute('SchemaVersion',4)
model:SetAttribute('Growth',.3);model:SetAttribute('WoodTriangles',800)
for k,v in P.Defaults do model:SetAttribute(k,v) end
local factory={isTree=function(m) return m==model end,setGrowth=function(m,v) m:SetAttribute('Growth',v) end,
	rebuild=function(m,p) for k,v in p do m:SetAttribute(k,v) end end}
local tree=harness('ParametricTreePlugin',{
	GrowthMath={},TreeAssetCatalog={Leaf={},Wood={}},TreeParameters=P,TreeSkeleton=stub(),TreeMesher=stub(),TreeMeshBackend=stub(),
	ProceduralTreeFactory=stub(factory),GrowthTreeFactory=stub(factory),
},{FindFirstChild=function() return nil end},{
	ContentProvider={PreloadAsync=function() end},ServerScriptService={FindFirstChild=function()
		return {GetAttribute=function(_,k) return if k=='BoraOwned' then true else '0.4.2' end}
	end},
})
tree.select.Items={model};tree.select.SelectionChanged:fire()
tree.history.Snapshot=function() local g=model:GetAttribute('Growth');return function() model:SetAttribute('Growth',g) end end
release=tree.gesture(tree.node('GrowthSlider'),40);release(80,'outside')
assert(model:GetAttribute('Growth')==.8 and tree.history.Commits==1)
release=tree.gesture(tree.node('GrowthSlider'),20);tree.window.WindowFocusReleased:fire();release(90,'widget')
assert(model:GetAttribute('Growth')==.8 and tree.history.Commits==1 and tree.history.Cancels==1)
release=tree.gesture(tree.node('BranchCountSlider'),40);assert(model:GetAttribute('BranchCount')==9)
release(100,'widget');assert(model:GetAttribute('BranchCount')==14 and tree.history.Commits==2)
print('PASS: actual map width and tree growth/branch sliders apply once through dock input and cancel safely.')
