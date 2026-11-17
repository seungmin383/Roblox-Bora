-- Execute actual Studio plugin callbacks against UI/history/query adapters.
-- The geometry generator itself is exercised separately with real Instances.
local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local json=require('@lune/serde')
local planModule=require('../src/BuildingPlan');local interiorModule=require('../src/BuildingInteriorFactory')
local P=require('../src/BuildingParameters');local widgets={};local buttons={};local events={}
local function event()
	local e={Callbacks={}};function e:Connect(fn)
		local slot={fn=fn,active=true};table.insert(self.Callbacks,slot);return {Disconnect=function() slot.active=false end}
	end
	function e:fire(...) for _,slot in table.clone(self.Callbacks) do if slot.active then slot.fn(...) end end end;return e
end
local function gui(class)
	local o={ClassName=class,InputBegan=event(),InputEnded=event(),MouseButton1Click=event(),AbsolutePosition=r.Vector2.new(16,0),AbsoluteSize=r.Vector2.new(350,16)}
	function o:GetPropertyChangedSignal(key) self.Changed=self.Changed or {};self.Changed[key]=self.Changed[key] or event();return self.Changed[key] end
	function o:Destroy() self.Destroyed=true end
	widgets[#widgets+1]=o;return o
end
local toolbar={}
function toolbar:CreateButton(id,_,_,text)
	local o={Click=event(),Text=text};function o:SetActive(value) self.Active=value end;buttons[id]=o;return o
end
local widget={WindowFocusReleased=event(),Enabled=false}
local pointer=r.Vector2.new(16,0)
function widget:GetRelativeMousePosition() return pointer end
function widget:BindToClose(fn) self.Close=fn end
function widget:Destroy() self.Destroyed=true end
local mouse={Move=event(),Button1Down=event(),UnitRay={Origin=r.Vector3.new(0,20,0),Direction=r.Vector3.new(0,-1,0)}}
local plugin={Deactivation=event(),Unloading=event()}
function plugin:CreateToolbar() return toolbar end
function plugin:CreateDockWidgetPluginGuiAsync() return widget end
function plugin:GetMouse() return mouse end
function plugin:Activate() end
function plugin:Deactivate() self.Deactivation:fire() end
local history={OnUndo=event(),OnRedo=event(),Commits=0,Records=0}
function history:TryBeginRecording() self.Records+=1;return 'record' end
function history:FinishRecording(_,op) if op==r.Enum.FinishRecordingOperation.Commit then self.Commits+=1 end end
local selection={Items={},SelectionChanged=event()};function selection:Get() return self.Items end
function selection:Set(items) self.Items=items;self.SelectionChanged:fire() end
local run={Heartbeat=event(),IsRunning=function() return false end}
local input={InputEnded=event(),InputBegan=event()}
local world={Collision=false};function world:FindFirstChild() return nil end
function world:GetPartBoundsInBox() return if self.Collision then {{CanCollide=true,Name='Neighbour'}} else {} end
function world:Raycast() return {Position=r.Vector3.zero,Normal=r.Vector3.yAxis} end
local edited={};local factory={Version='1.4.0',isBuilding=function(m) return m:GetAttribute('AssetKind')=='BoraBuilding' end,keepsShell=function() return false end}
function factory.rebuild(m,p) P.write(m,p);table.insert(edited,{Model=m,Parameters=p});return {} end
local parent={BuildingParameters={},BuildingFactory={},BuildingPlan={},BuildingInteriorFactory={},BuildingPlanEditor={},DockPointer={}};function parent:FindFirstChild() return nil end
local existingRuntime={GetAttribute=function(_,key) return if key=='BoraOwned' then true else '1.4.0' end,SetAttribute=function() end}
local pointerModule=compiler.load(fs.readFile('src/DockPointer.luau'))
setfenv(pointerModule,setmetatable({Enum=r.Enum},{__index=getfenv()}))
local DockPointer=pointerModule()
local planBridge
local function openPlan(_,_,_,_,bridge)
	planBridge=bridge;return {Open=function() end,Refresh=function() end,Destroy=function() end}
end
local runtimeParent={FindFirstChild=function() return existingRuntime end}
local starter={FindFirstChildOfClass=function() return runtimeParent end}
local http={JSONDecode=function(_,s) return json.decode('json',s) end,JSONEncode=function(_,v) return json.encode('json',v) end}
local env=setmetatable({plugin=plugin,script={Parent=parent},workspace=world,
	game={GetService=function(_,name) return ({Selection=selection,ChangeHistoryService=history,UserInputService=input,RunService=run,HttpService=http,ServerScriptService=runtimeParent,StarterPlayer=starter})[name] end},
	require=function(item)
		return if item==parent.BuildingParameters then P elseif item==parent.BuildingPlan then planModule elseif item==parent.BuildingInteriorFactory then interiorModule
			elseif item==parent.BuildingPlanEditor then openPlan elseif item==parent.DockPointer then DockPointer else function() return factory end
	end,
	Instance={new=gui},Enum=r.Enum,UDim2=r.UDim2,UDim=r.UDim,Vector2=r.Vector2,Vector3=r.Vector3,CFrame=r.CFrame,Color3=r.Color3,
	DockWidgetPluginGuiInfo={new=function() return {} end},OverlapParams={new=function() return {} end},RaycastParams={new=function() return {} end},
},{__index=getfenv()})
local fn=compiler.load(fs.readFile('src/BuildingEditorPlugin.server.luau'));setfenv(fn,env);fn()
local function text(value)
	for _,o in widgets do if o.Text==value then return o end end;error('UI not found: '..value)
end
local b=r.Instance.new('Model');P.write(b,{Floors=3,Title='기존 상가'})
b.Parent=r.Instance.new('Folder');local origin=r.Instance.new('Part');origin.Name,origin.Parent='BuildingOrigin',b
local child=r.Instance.new('Part');child.Parent=b
selection:Set({child});assert(widget.Enabled and text('기존 상가'),'Selecting a descendant did not load the recipe')
text('기존 상가').Text='새 가게 이름';text('선택한 건물에 적용').MouseButton1Click:fire()
assert(#edited==1 and edited[1].Model==b and P.read(b).Title=='새 가게 이름' and history.Commits==1)
-- Numeric input must not silently fall back to defaults, nor enter history.
local widthBox=text('12');widthBox.Text='wrong';text('선택한 건물에 적용').MouseButton1Click:fire()
assert(#edited==1 and history.Records==1)
widthBox.Text='13';world.Collision=true;text('선택한 건물에 적용').MouseButton1Click:fire()
assert(#edited==1 and history.Records==1,'Colliding edit committed')
world.Collision=false;text('선택한 건물에 적용').MouseButton1Click:fire();assert(P.read(b).Width==13)
-- A nearby exterior collider must not reject an interior movement that does
-- not change the building footprint; the main size editor remains protected.
buttons.BoraBuildingPlan_v1.Click:fire();assert(planBridge and planBridge.Get()==b)
world.Collision=true
local plan='{"Items":[{"Id":1,"Kind":"Stairs","Floor":1,"X":0.25,"Z":0,"Rotation":0}]}'
assert(planBridge.Apply(b,plan) and P.read(b).PlanJSON==plan and P.read(b).Width==13)
world.Collision=false
-- First slider controls floor count; only release commits an edit.
local tracks={};for _,o in widgets do if o.ClassName=='TextButton' and o.Text=='' and o.AutoButtonColor==false then table.insert(tracks,o) end end
local stateChange=event()
local dragInput={UserInputType=r.Enum.UserInputType.MouseButton1,UserInputState=r.Enum.UserInputState.Begin,GetPropertyChangedSignal=function() return stateChange end}
pointer=r.Vector2.new(366,0);local count=#edited
tracks[1].InputBegan:fire(dragInput);assert(#edited==count,'Slider rebuilt geometry for each pointer event')
input.InputEnded:fire(dragInput);assert(#edited==count)
tracks[1].InputEnded:fire(dragInput);assert(#edited==count+1 and P.read(b).Floors==24)
-- An Escape-cancelled drag must preserve recipe and input field.
pointer=r.Vector2.new(16,0);tracks[1].InputBegan:fire(dragInput)
tracks[1].InputBegan:fire({KeyCode=r.Enum.KeyCode.Escape});dragInput.UserInputState=r.Enum.UserInputState.End
stateChange:fire();assert(#edited==count+1 and P.read(b).Floors==24)
-- Click placement mode toggles the ghost and cancellation removes it.
buttons.BoraBuildingPlace_v1.Click:fire();assert(buttons.BoraBuildingPlace_v1.Active)
input.InputBegan:fire({KeyCode=r.Enum.KeyCode.Escape});assert(not buttons.BoraBuildingPlace_v1.Active)
print('PASS: actual building plugin descendant selection, Korean rename, invalid input, collision refusal, slider release, Ctrl+Z recording and Escape.')
