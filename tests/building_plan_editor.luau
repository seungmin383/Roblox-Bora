-- Run the real canvas callbacks. Coordinates share the geometry recipe's metres.
local r,fs,compiler,json=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau'),require('@lune/serde')
local P=require('../src/BuildingParameters');local B=require('../src/BuildingPlan')({Decode=function(s) return json.decode('json',s) end,Encode=function(v) return json.encode('json',v) end})
local function event()
	local e={Callbacks={}}
	function e:Connect(fn)
		local slot={fn=fn,active=true};table.insert(self.Callbacks,slot)
		return {Disconnect=function() slot.active=false end}
	end
	function e:fire(...) for _,slot in table.clone(self.Callbacks) do if slot.active then slot.fn(...) end end end;return e
end
local objects={}
local function gui(class)
	local o={ClassName=class,MouseButton1Click=event(),InputBegan=event(),InputEnded=event(),FocusLost=event(),AbsoluteSize=r.Vector2.new(680,570),AbsolutePosition=r.Vector2.new(16,168)}
	function o:GetPropertyChangedSignal() return event() end
	function o:GetChildren() local children={};for _,v in objects do if v.Parent==self and not v.Destroyed then table.insert(children,v) end end;return children end
	function o:Destroy() for _,child in self:GetChildren() do child:Destroy() end;self.Destroyed=true end
	table.insert(objects,o);return o
end
local pointer=r.Vector2.new(0,0);local widget={Enabled=false,WindowFocusReleased=event()}
function widget:GetRelativeMousePosition() return pointer end
function widget:BindToClose(fn) self.Close=fn end;function widget:Destroy() end
local plugin={CreateDockWidgetPluginGuiAsync=function() return widget end}
local run={IsRunning=function() return false end,Heartbeat=event()}
local target=r.Instance.new('Model');target.Parent=r.Instance.new('Folder');P.write(target,{Width=16,Depth=12,Floors=3})
local commits=0;local oldJson={}
local F=require('../src/BuildingFactory')(r,P,nil,B,require('../src/BuildingInteriorFactory')(r,B))
local bridge={Get=function() return target end,Apply=function(_,s)
	table.insert(oldJson,P.read(target).PlanJSON);local p=P.read(target);p.PlanJSON=s
	if F.isBuilding(target) then F.rebuild(target,p) else P.write(target,p) end
	commits+=1;return true
end}
local env=setmetatable({Instance={new=gui},Enum=r.Enum,UDim=r.UDim,UDim2=r.UDim2,Vector2=r.Vector2,Color3=r.Color3,DockWidgetPluginGuiInfo={new=function() return {} end}},{__index=getfenv()})
local chunk=compiler.load(fs.readFile('src/BuildingPlanEditor.luau'));setfenv(chunk,env)
local pointerModule=compiler.load(fs.readFile('src/DockPointer.luau'));setfenv(pointerModule,env)
-- No viewport UserInputService exists inside this harness, as in a focused dock widget.
local controller=chunk()(plugin,{Run=run,Pointer=pointerModule()},P,B,bridge);controller.Open();assert(widget.Enabled)
local function named(name) for _,o in objects do if o.Name==name and not o.Destroyed then return o end end;error('Missing UI '..name) end
local function button(name) named(name).MouseButton1Click:fire() end
local scale=math.min((680-70)/16,(570-70)/12)
local states=r.Enum.UserInputState
local lastPress,lastTrack
local function pressHere(track)
	local changed=event()
	local input={UserInputType=r.Enum.UserInputType.MouseButton1,UserInputState=states.Begin}
	function input:GetPropertyChangedSignal(property) assert(property=='UserInputState');return changed end
	function input:set(state,notify)
		self.UserInputState=state;if notify then changed:fire() end
	end
	lastPress,lastTrack=input,track or named('PlanInput')
	lastTrack.InputBegan:fire(input);return input
end
local function release(mode)
	local input,track=lastPress,lastTrack;lastPress,lastTrack=nil,nil
	if not input then return end
	input:set(states.End,mode~='widget' and mode~='heartbeat')
	if mode=='heartbeat' then run.Heartbeat:fire(.05)
	elseif mode~='outside' then track.InputEnded:fire(input) end
end
local function esc() named('PlanInput').InputBegan:fire({KeyCode=r.Enum.KeyCode.Escape}) end
local function pointerAt(x,z) pointer=r.Vector2.new(16+340+x*scale,168+285-z*scale) end
local function press(x,z)
	pointerAt(x,z)
	return pressHere()
end
local function click(x,z) press(x,z);release() end
local function saved() return B.decode(P.read(target).PlanJSON,P.read(target)) end
button('PlanToolWall');click(0,-4.5);assert(commits==0);click(0,2);assert(commits==1 and saved().Items[1].Kind=='Wall')
button('PlanToolStairs');click(-4.5,1);assert(commits==2 and saved().Items[2].Floor==1)
button('NextFloor');button('PlanToolStairs');click(-4.5,1);assert(commits==3 and saved().Items[3].Floor==2)
button('PlanToolElevator');click(4.5,2);assert(commits==4 and saved().Items[4].Floor==1)
button('PlanToolBlock');click(1,-2);click(2,-1);assert(commits==5 and saved().Items[5].Width==1)
-- Overlapping a core or stepping beyond the facade never changes saved geometry.
button('PlanToolStairs');click(4.5,2);assert(commits==5)
click(20,2);assert(commits==5)
-- Canvas drag moves the same ID; rotation and deletion each create one commit.
button('PlanToolSelect');press(1.5,-1.5)
pointerAt(2,-2)
release('widget');assert(commits==6)
button('RotateSelection');assert(commits==7 and saved().Items[5].Rotation==90)
button('DeleteSelection');assert(commits==8 and #saved().Items==4)
button('PlanToolWall');click(-1,-3);esc();click(-1,-2);assert(commits==8)
esc()
-- An empty explicit plan and the prior automatic plan remain distinguishable.
local last=oldJson[#oldJson];assert(type(last)=='string' and #last>0)
local function reset(items,real,floors)
	local config=P.normalize({Width=16,Depth=12,Floors=floors or 3});config.PlanJSON=B.encode({Version=1,Items=items},config)
	target=if real then F.create(config,r.CFrame.new()) else r.Instance.new('Model')
	target.Parent=r.Instance.new('Folder');P.write(target,config);controller.Refresh()
	named('FloorNumber').Text='1';named('FloorNumber').FocusLost:fire()
	assert(not named('PlanPivot').Visible)
end
local function startHandle(key)
	local h=named('PlanGizmo'..key);pointer=r.Vector2.new(16+h.Position.X.Offset,168+h.Position.Y.Offset)
	pressHere()
	return (pointer.X-16-340)/scale,(285-(pointer.Y-168))/scale
end
local function near(a,b) assert(math.abs(a-b)<.00001, tostring(a)..' ~= '..tostring(b)) end
local function center(x,z) local a,b=B.center(saved().Items[1]);near(a,x);near(b,z) end
-- Axis handles constrain movement; previews never mutate saved recipes.
reset({{Id=1,Kind='Wall',Floor=1,X=-2,Z=0,X2=2,Z2=0,Thickness=.16}})
button('PlanToolSelect');click(1,0);release();assert(named('PlanPivot').Visible)
local count=commits
local x,z=startHandle('X');pointerAt(x+1,z+1);run.Heartbeat:fire(.05);assert(commits==count);center(0,0)
release();assert(commits==count+1);center(1,0)
x,z=startHandle('Z');pointerAt(x+.5,z+1);release();center(1,1)
x,z=startHandle('XNegative');pointerAt(x-.5,z+.75);release();center(.5,1)
x,z=startHandle('ZNegative');pointerAt(x+.75,z-.5);release();center(.5,.5)
x,z=startHandle('Move');pointerAt(x+.25,z-.5);release();center(.75,0)
-- Rotation occurs about the midpoint and preserves wall length and ID.
x,z=startHandle('Rotate');local cx,cz=B.center(saved().Items[1]);local start=math.atan2(-(z-cz),x-cx)
pointerAt(cx+1.5*math.cos(start+math.rad(31)),cz-1.5*math.sin(start+math.rad(31)))
count=commits;run.Heartbeat:fire(.05);assert(commits==count);release();assert(commits==count+1)
local wall=saved().Items[1];near(B.angle(wall),30);center(.75,0);near((wall.X2-wall.X)^2+(wall.Z2-wall.Z)^2,16);assert(wall.Id==1)
-- Explicit coordinates support absolute angles; invalid input is atomic.
named('PivotX').Text='-1';named('PivotZ').Text='-1';named('PivotAngle').Text='45';button('ApplyPivot');center(-1,-1);near(B.angle(saved().Items[1]),45)
count=commits;local before=P.read(target).PlanJSON;named('PivotX').Text='100';button('ApplyPivot');assert(commits==count and P.read(target).PlanJSON==before)
named('PivotX').Text='nan';button('ApplyPivot');assert(commits==count)
x,z=startHandle('X');pointerAt(x+100,z);release();assert(commits==count and P.read(target).PlanJSON==before)
x,z=startHandle('Move');pointerAt(x+1,z+1);run.Heartbeat:fire(.05);esc();release();assert(commits==count and P.read(target).PlanJSON==before)
-- Stairs, lifts and wall blocks share the same pivot and quarter-turn snap.
for _,kind in {'Stairs','Elevator','Block'} do
	reset({{Id=1,Kind=kind,Floor=1,X=0,Z=0,Width=1,Depth=2,Rotation=0}})
	click(0,0);release();x,z=startHandle('Rotate');local a=math.atan2(-z,x)
	pointerAt(1.5*math.cos(a+math.rad(27)),-1.5*math.sin(a+math.rad(27)));count=commits;release();assert(commits==count)
	x,z=startHandle('Rotate');a=math.atan2(-z,x);pointerAt(1.5*math.cos(a+math.rad(110)),-1.5*math.sin(a+math.rad(110)))
	run.Heartbeat:fire(.05);assert(commits==count);release();assert(commits==count+1 and saved().Items[1].Rotation==90);center(0,0)
end
-- Losing selection or switching floors cancels any in-progress gesture.
x,z=startHandle('Move');pointerAt(x+1,z+1);button('NextFloor');count=commits;release();assert(commits==count and not named('PlanPivot').Visible)
target=nil;controller.Refresh();assert(not named('PlanPivot').Visible)
reset({{Id=1,Kind='Wall',Floor=1,X=-3,Z=0,X2=3,Z2=0,Thickness=.16},
	{Id=2,Kind='Wall',Floor=1,X=0,Z=2,X2=1,Z2=2,Thickness=.16}})
count=commits;button('PlanToolDoor');click(0,2);assert(commits==count)
click(-1,0);assert(commits==count+1);near(saved().Items[1].DoorAt,2/6)
click(1,0);assert(commits==count+2);near(saved().Items[1].DoorAt,4/6)
button('RotateSelection');assert(commits==count+3 and saved().Items[1].DoorAt==4/6)
click(0,-1);assert(commits==count+4 and saved().Items[1].DoorAt==nil)
-- Reproduce the report with actual 3D regeneration: place a stair, then move it
-- from its own floor and from its arrival on the upper floor.
target=F.create({Width=16,Depth=12,Floors=3},r.CFrame.new());target.Parent=r.Instance.new('Folder');controller.Refresh()
button('PlanToolStairs');count=commits;click(-4,0)
assert(commits==count+1 and named('PlanPivot').Visible);center(-4,0)
local initialTread=target.Geometry.FloorPlanInterior.Stairs_1:FindFirstChild('LowerTread').CFrame.Position
x,z=startHandle('Z');pointerAt(x+1,z+.5);run.Heartbeat:fire(.05);assert(commits==count+1)
release('outside');assert(commits==count+2);center(-4,.5)
local movedTread=target.Geometry.FloorPlanInterior.Stairs_1:FindFirstChild('LowerTread').CFrame.Position
assert(math.abs((movedTread.Z-initialTread.Z)*.28-.5)<.0001)
button('NextFloor');press(-4,.5);pointerAt(-3,.75);release('heartbeat')
assert(commits==count+3 and saved().Items[1].Floor==1);center(-3,.75)
local opening=B.holes(saved(),2)[1];near((opening.X0+opening.X1)*.5,-3)
x,z=startHandle('Move');pointerAt(x+1,z+1);lastPress:set(states.Cancel,true);release()
assert(commits==count+3)
-- A stair belonging to the current floor takes priority over the arrival underneath.
button('PlanToolStairs');click(-3,.75);assert(commits==count+4)
button('PreviousFloor');button('NextFloor');press(-3,.75);pointerAt(-2.5,.75);release('widget')
assert(commits==count+5 and saved().Items[2].X==-2.5 and saved().Items[1].X==-3)
-- Copy the selected middle floor, replace other floors atomically, preserve
-- the source IDs and shared elevator, and restore the exact old recipe.
reset({
	{Id=1,Kind='Wall',Floor=1,X=-2,Z=-3,X2=2,Z2=-3,Thickness=.2},
	{Id=2,Kind='Wall',Floor=2,X=-2,Z=-2.75,X2=2,Z2=-2.75,Thickness=.18,DoorAt=.55},
	{Id=3,Kind='Stairs',Floor=2,X=-4,Z=1,Rotation=0},
	{Id=4,Kind='Block',Floor=3,X=0,Z=1,Width=1,Depth=1,Rotation=0},
	{Id=5,Kind='Elevator',Floor=1,X=4,Z=1,Rotation=0},
},true)
button('NextFloor');count=commits;before=P.read(target).PlanJSON
assert(not named('UndoFloorCopy').Active)
button('CopyAllFloors');assert(commits==count+1 and named('UndoFloorCopy').Active and named('FloorNumber').Text=='2')
local stairs,walls,lifts,ids={},{},0,{}
for _,e in saved().Items do
	assert(not ids[e.Id]);ids[e.Id]=true
	if e.Kind=='Stairs' then stairs[e.Floor]=e elseif e.Kind=='Wall' then walls[e.Floor]=e
	elseif e.Kind=='Elevator' then lifts+=1;assert(e.Id==5) else error('Old block not overwritten') end
end
assert(lifts==1 and stairs[1] and stairs[2].Id==3 and not stairs[3] and walls[2].Id==2)
for floor=1,3 do
	assert(walls[floor].DoorAt==.55 and walls[floor].Thickness==.18)
	assert(target.Geometry.FloorPlanInterior['PlanWall_'..walls[floor].Id]:FindFirstChild('DoorHeader'))
end
button('UndoFloorCopy');assert(commits==count+2 and P.read(target).PlanJSON==before and not named('UndoFloorCopy').Active)
assert(target.Geometry.FloorPlanInterior:FindFirstChild('PlanBlock_4') and not target.Geometry.FloorPlanInterior:FindFirstChild('Stairs_'..stairs[1].Id))
button('CopyFloor');assert(commits==count+2,'Next floor copy unexpectedly overwrote the occupied top floor')
-- Reject a full copy that would exceed the part limit, without touching any floor.
local many={}
for id=1,12 do table.insert(many,{Id=id,Kind='Wall',Floor=1,X=-1,Z=id*.25,X2=1,Z2=id*.25,Thickness=.16}) end
reset(many,false,24);count=commits;before=P.read(target).PlanJSON
button('CopyAllFloors');assert(commits==count and P.read(target).PlanJSON==before and not named('UndoFloorCopy').Active)
-- Next-floor copying and undo still work on a free destination.
reset({{Id=1000000,Kind='Wall',Floor=1,X=-2,Z=0,X2=2,Z2=0,Thickness=.16}},true)
count=commits;before=P.read(target).PlanJSON
button('CopyFloor');assert(commits==count+1 and saved().Items[2].Floor==2 and saved().Items[2].Id~=1000000)
button('UndoFloorCopy');assert(commits==count+2 and P.read(target).PlanJSON==before)
button('PreviousFloor')
-- Unity-style label scrubbing previews values, commits once, and changes the 3D wall.
button('PlanToolSelect');click(0,0);count=commits
local function scrub(name,delta)
	pointer=r.Vector2.new(290,133);pressHere(named(name))
	pointer=r.Vector2.new(290+delta,133);run.Heartbeat:fire(.05)
end
scrub('PivotXScrub',25)
assert(commits==count);near(tonumber(named('PivotX').Text),.75);center(0,0)
release('widget');assert(commits==count+1);center(.75,0)
scrub('PivotZScrub',-16);release('outside');center(.75,-.5)
scrub('WallThicknessScrub',20);near(tonumber(named('WallThickness').Text),.2);near(saved().Items[1].Thickness,.16)
release('heartbeat');assert(commits==count+3);near(saved().Items[1].Thickness,.2)
near(target.Geometry.FloorPlanInterior.PlanWall_1000000.Size.X*.28,.2)
scrub('WallThicknessScrub',200);near(tonumber(named('WallThickness').Text),.4)
named('WallThicknessScrub').InputBegan:fire({KeyCode=r.Enum.KeyCode.Escape});release()
assert(commits==count+3);near(tonumber(named('WallThickness').Text),.20)
scrub('PivotAngleScrub',12);release('widget');near(B.angle(saved().Items[1]),15)
named('WallThickness').Text='0.27';named('WallThickness').FocusLost:fire(true);near(saved().Items[1].Thickness,.27)
-- With no selected wall, thickness controls only subsequently drawn walls.
button('PlanToolWall');count=commits;scrub('WallThicknessScrub',25);release('widget');assert(commits==count)
click(-2,2);click(2,2);assert(commits==count+1);near(saved().Items[2].Thickness,.21)
-- A stale rollback cannot clobber a later plan edit.
button('CopyAllFloors');assert(named('UndoFloorCopy').Active)
button('PlanToolSelect');click(0,2);scrub('WallThicknessScrub',10);release();assert(not named('UndoFloorCopy').Active)
before=P.read(target).PlanJSON;button('UndoFloorCopy');assert(P.read(target).PlanJSON==before)
local out=require('@lune/process').env.BORA_VILLA_WORK
if out then fs.writeFile(out..'/building-gizmo-validation.json',json.encode('json',{Passed=true,AxisConstrained=true,WallCenterAndLengthPreserved=true,RotationSnap={Wall=15,Others=90},PreviewDoesNotCommit=true,ReleaseCommitsOnce=true,InvalidEditsAtomic=true,EscapeAndFloorChangeCancel=true,DoorPlaceMoveRemove=true,StudioUIOpened=false})) end
controller.Destroy()
print('PASS: real floor plan handlers, all-floor/next-floor copy and guarded restore, X/Z/angle/thickness scrubbing, 3D regeneration, doors and cancellation.')
