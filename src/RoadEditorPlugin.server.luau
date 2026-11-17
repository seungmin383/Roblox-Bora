if not plugin then return end
local RunService=game:GetService('RunService')
if RunService:IsRunning() then return end
local Selection=game:GetService('Selection')
local History=game:GetService('ChangeHistoryService')
local Input=game:GetService('UserInputService')
local DockPointer=require(script.Parent.DockPointer)
local Http=game:GetService('HttpService')
local snapshots={}
local api={Instance=Instance,Vector3=Vector3,Vector2=Vector2,CFrame=CFrame,Color3=Color3,Enum=Enum,UDim2=UDim2}
api.Retire=function(item) item.Parent=nil; table.insert(snapshots,item) end
local Path=require(script.Parent.RoadPath)(Vector3)
local Lanes=require(script.Parent.LaneDirections)(api,Path)
local Traffic=require(script.Parent.RoadTraffic)(api,Path,Lanes,require(script.Parent.TrafficAssetLayout))
local Roads=require(script.Parent.RoadNetworkFactory)(api,Path,Traffic)
local Junctions=require(script.Parent.RoadJunctions)(Vector3,Path)
local Network=require(script.Parent.RoadNetwork)(api,Path,Roads,Junctions,Traffic,Lanes)
local Guides=require(script.Parent.MapGuideFactory)(api)
local toolbar=plugin:CreateToolbar('보라동 도로')
local openButton=toolbar:CreateButton('BoraRoadEditor','지도 위에 점을 찍어 도로를 그립니다.','','지도 · 도로')
local widget=plugin:CreateDockWidgetPluginGuiAsync('BoraRoadInspector_v1_float',DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,false,true,360,820,330,500))
widget.Title='지도 · 도로 편집'
local background=Instance.new('Frame')
background.Size,background.BackgroundColor3,background.BorderSizePixel,background.Parent=UDim2.fromScale(1,1),Color3.fromRGB(30,34,40),0,widget
local scroll=Instance.new('ScrollingFrame')
scroll.Name,scroll.Position,scroll.Size='Controls',UDim2.fromOffset(0,48),UDim2.new(1,0,1,-132)
scroll.CanvasSize,scroll.ScrollBarThickness,scroll.BackgroundTransparency,scroll.BorderSizePixel=UDim2.fromOffset(0,665),5,1,0
scroll.Parent=background
local mapPage=Instance.new('Frame'); mapPage.Name='MapControls'
mapPage.Size,mapPage.BackgroundTransparency,mapPage.Parent=UDim2.new(1,0,0,660),1,scroll
local roadPage=mapPage:Clone(); roadPage.Name,roadPage.Visible,roadPage.Parent='RoadControls',false,scroll
local lanePage=mapPage:Clone(); lanePage.Name,lanePage.Visible,lanePage.Parent='LaneControls',false,scroll
local refreshLanes,leaveLaneMode
local function text(parent,name,value,x,y,width,height,size)
	local item=Instance.new('TextLabel')
	item.Name,item.Text,item.Position,item.Size=name,value,UDim2.fromOffset(x,y),width or UDim2.new(1,-24,0,height or 26)
	item.BackgroundTransparency,item.TextColor3,item.TextSize=1,Color3.fromRGB(230,235,237),size or 15
	item.Font,item.TextXAlignment,item.TextWrapped=Enum.Font.SourceSans,Enum.TextXAlignment.Left,true
	item.Parent=parent; return item
end
local function button(parent,name,value,x,y,size)
	local item=Instance.new('TextButton')
	item.Name,item.Text,item.Position,item.Size=name,value,UDim2.fromOffset(x,y),size or UDim2.new(1,-24,0,34)
	item.BackgroundColor3,item.TextColor3,item.Font,item.TextSize=Color3.fromRGB(65,111,99),Color3.new(1,1,1),Enum.Font.SourceSansSemibold,16
	item.Parent=parent; return item
end
local function box(parent,name,value,x,y,size)
	local item=Instance.new('TextBox')
	item.Name,item.Text,item.ClearTextOnFocus=name,tostring(value),false
	item.Position,item.Size=UDim2.fromOffset(x,y),size or UDim2.fromOffset(80,29)
	item.BackgroundColor3,item.TextColor3,item.Font,item.TextSize=Color3.fromRGB(47,54,63),Color3.fromRGB(243,241,227),Enum.Font.SourceSans,17
	item.Parent=parent; return item
end
local mapTab=button(background,'MapTab','지도 · 축척',12,7,UDim2.new(1/3,-16,0,33))
local roadTab=button(background,'RoadTab','도로 그리기',0,7,UDim2.new(1/3,-16,0,33))
roadTab.Position=UDim2.new(1/3,6,0,7)
local laneTab=button(background,'LaneTab','차로 방향',0,7,UDim2.new(1/3,-16,0,33)); laneTab.Position=UDim2.new(2/3,0,0,7)
local status=text(background,'Status','지도 축척을 먼저 맞추고 도로를 그리세요.',12,0,nil,72,15)
status.Position,status.Size=UDim2.new(0,12,1,-77),UDim2.new(1,-24,0,72)
local function showTab(road)
	if leaveLaneMode then leaveLaneMode() end
	lanePage.Visible=false; laneTab.BackgroundColor3=Color3.fromRGB(49,57,65)
	mapPage.Visible,roadPage.Visible=not road,road
	mapTab.BackgroundColor3=if road then Color3.fromRGB(49,57,65) else Color3.fromRGB(65,111,99)
	roadTab.BackgroundColor3=if road then Color3.fromRGB(65,111,99) else Color3.fromRGB(49,57,65)
	scroll.CanvasPosition=Vector2.zero
	scroll.CanvasSize=UDim2.fromOffset(0,if road then 1435 else 665)
end
mapTab.Activated:Connect(function() showTab(false) end)
roadTab.Activated:Connect(function() showTab(true) end)
local function showLaneTab()
	mapPage.Visible,roadPage.Visible,lanePage.Visible=false,false,true
	mapTab.BackgroundColor3,roadTab.BackgroundColor3,laneTab.BackgroundColor3=Color3.fromRGB(49,57,65),Color3.fromRGB(49,57,65),Color3.fromRGB(65,111,99)
	scroll.CanvasPosition=Vector2.zero;scroll.CanvasSize=UDim2.fromOffset(0,700)
	if refreshLanes then refreshLanes() end
end
laneTab.Activated:Connect(showLaneTab)
local mapFields,roadFields,trafficFields,sliders={},{},{},{}
local activeSlider=nil
local function paint(control)
	local value=tonumber(control.Input.Text)
	if not value or value~=value then return end
	local ratio=math.clamp((value-control.Min)/(control.Max-control.Min),0,1)
	control.Fill.Size,control.Handle.Position=UDim2.fromScale(ratio,1),UDim2.fromScale(ratio,.5)
end
local function slider(parent,fields,name,title,value,minimum,maximum,step,y)
	text(parent,name..'Label',title,12,y,UDim2.new(1,-112,0,28))
	local input=box(parent,name..'Input',value,0,y)
	input.Position=UDim2.new(1,-92,0,y)
	fields[name]=input
	local bar=button(parent,name..'Slider','',12,y+34,UDim2.new(1,-24,0,15)); bar.AutoButtonColor=false
	bar.BackgroundColor3=Color3.fromRGB(65,73,80)
	local fill=Instance.new('Frame'); fill.BackgroundColor3,fill.BorderSizePixel,fill.Parent=Color3.fromRGB(97,159,132),0,bar
	local handle=Instance.new('Frame'); handle.Name='Handle'
	handle.Size,handle.AnchorPoint,handle.BackgroundColor3,handle.BorderSizePixel,handle.Parent=UDim2.fromOffset(7,23),Vector2.new(.5,.5),Color3.fromRGB(220,239,221),0,bar
	local control={Input=input,Track=bar,Fill=fill,Handle=handle,Min=minimum,Max=maximum,Step=step,Page=parent,Name=name}
	table.insert(sliders,control); paint(control)
	input:GetPropertyChangedSignal('Text'):Connect(function() paint(control) end)
	return control
end
local topButton=button(mapPage,'MapTopView','지도 위에서 보기',12,0,UDim2.new(.5,-18,0,34))
local visibility=button(mapPage,'MapVisibility','지도 숨기기',0,0,UDim2.new(.5,-18,0,34)); visibility.Position=UDim2.new(.5,6,0,0)
text(mapPage,'MapImageLabel','지도 이미지 주소 / Roblox 이미지 ID',12,42)
mapFields.Image=box(mapPage,'MapImage',Guides.DefaultImage,12,66,UDim2.new(1,-24,0,29))
slider(mapPage,mapFields,'Width','지도 가로 폭 · studs',1200,100,16000,10,105)
slider(mapPage,mapFields,'Rotation','지도 회전 · °',0,-180,180,1,165)
slider(mapPage,mapFields,'Opacity','지도 진하기 · %',90,0,100,1,225)
text(mapPage,'DistanceLabel','기준점 사이 실제 거리 · m',12,289,UDim2.new(1,-112,0,28))
mapFields.Distance=box(mapPage,'CalibrationMeters',100,0,289); mapFields.Distance.Position=UDim2.new(1,-92,0,289)
local calibrate=button(mapPage,'StartCalibration','축척 맞추기 · 지도에서 두 점 찍기',12,329)
local calibrationLabel=text(mapPage,'CalibrationState','현재 축척 미확정 · 실제 거리를 먼저 입력하세요.',12,373,UDim2.new(1,-24,0,43))
text(mapPage,'MapPositionLabel','지도 중심 위치 · X / Z (studs)',12,424)
mapFields.X=box(mapPage,'MapCenterX',850,12,451,UDim2.new(.5,-18,0,29))
mapFields.Z=box(mapPage,'MapCenterZ',0,0,451,UDim2.new(.5,-18,0,29)); mapFields.Z.Position=UDim2.new(.5,6,0,451)
local applyMap=button(mapPage,'ApplyMap','지도 설정 적용',12,492)
text(mapPage,'MapPixelsLabel','이미지 가로 / 세로 픽셀',12,536)
mapFields.PixelWidth=box(mapPage,'MapPixelWidth',3970,12,564,UDim2.new(.5,-18,0,29))
mapFields.PixelHeight=box(mapPage,'MapPixelHeight',2036,0,564,UDim2.new(.5,-18,0,29)); mapFields.PixelHeight.Position=UDim2.new(.5,6,0,564)
text(mapPage,'MapHint','축척 변경은 지도에만 적용됩니다. 도로를 그리기 전에 맞추세요. 지도는 Play에서 숨겨집니다.',12,607,UDim2.new(1,-24,0,48),48,14)
local drawButton=button(roadPage,'DrawRoad','새 도로 그리기',12,0,UDim2.new(.5,-18,0,34))
local finishButton=button(roadPage,'FinishRoad','도로 확정 · Enter',0,0,UDim2.new(.5,-18,0,34)); finishButton.Position=UDim2.new(.5,6,0,0)
local editButton=button(roadPage,'EditRoad','선택 도로 · 점 편집',12,43,UDim2.new(.5,-18,0,34))
local cancelButton=button(roadPage,'CancelRoad','작업 취소 · Esc',0,43,UDim2.new(.5,-18,0,34)); cancelButton.Position=UDim2.new(.5,6,0,43)
text(roadPage,'RoadHint','클릭: 점 추가 · Enter: 확정 · Backspace: 마지막 점 취소',12,84,UDim2.new(1,-24,0,30),30,14)
local presets={}
for i,title in {'골목','왕복 2차선','왕복 4차선'} do
	local b=button(roadPage,'Preset'..i,title,12,118,UDim2.new(1/3,-16,0,29))
	b.Position=UDim2.new((i-1)/3,12,0,118); presets[i]=b
end
for _,spec in {{'Width','도로 폭 · m',7,2.5,24,.1},{'Lanes','전체 차선 수',2,1,6,1},{'Sidewalk','양쪽 인도 폭 · m',1.5,0,5,.1},{'Curve','곡선의 완만함 · %',75,0,100,1},{'Lift','노면 높이 보정 · m',.05,0,2,.01}} do
	local i=#sliders-2
	slider(roadPage,roadFields,spec[1],spec[2],spec[3],spec[4],spec[5],spec[6],158+(i-1)*58)
end
local applyRoad=button(roadPage,'ApplyRoad','도로 설정 적용',12,452)
text(roadPage,'NodeHeightLabel','선택한 점의 높이 · m',12,496,UDim2.new(1,-112,0,28))
roadFields.NodeHeight=box(roadPage,'NodeHeight',0,0,496); roadFields.NodeHeight.Position=UDim2.new(1,-92,0,496)
local heightButton=button(roadPage,'ApplyNodeHeight','선택한 점 높이 적용',12,535)
local insertButton=button(roadPage,'InsertNode','도로 위를 클릭해 점 추가',12,578,UDim2.new(.6,-18,0,34))
local removeButton=button(roadPage,'RemoveNode','선택 점 삭제',0,578,UDim2.new(.4,-18,0,34)); removeButton.Position=UDim2.new(.6,6,0,578)
text(roadPage,'ConnectionHint','도로를 가로질러 그리거나 T자 반대편에 붙이면 십자로 연결됩니다. 확정할 때 인도·차선을 정리합니다.',12,624,UDim2.new(1,-24,0,45),45,14)
local refreshNetwork=button(roadPage,'RefreshJunctions','교차로 다시 계산',12,680)
text(roadPage,'TrafficTitle','교차로 시설 · 전체 도로에 적용',12,725)
local trafficToggles,trafficValues={},table.clone(Traffic.Defaults)
for i,spec in {{'Crosswalks','횡단보도'},{'StopLines','정지선'},{'Signals','차량 신호'}} do
	local b=button(roadPage,spec[1],spec[2]..' 켜짐',12,756,UDim2.new(1/3,-16,0,31))
	b.Position=UDim2.new((i-1)/3,12,0,756); trafficToggles[spec[1]]={Button=b,Label=spec[2]}
end
local pedestrianToggle=button(roadPage,'PedestrianSignals','보행 신호 켜짐',12,795)
trafficToggles.PedestrianSignals={Button=pedestrianToggle,Label='보행 신호'}
for i,spec in {{'CrosswalkWidth','횡단보도 깊이 · m',3,2,6,.1},{'CrosswalkOffset','교차로에서 띄우기 · m',.6,0,5,.1},{'StopGap','횡단보도 → 정지선 · m',1,.5,4,.1},{'GreenSeconds','직진 초록불 유지 · 초',12,5,60,1},{'LeftSeconds','좌회전 화살표 유지 · 초',8,4,40,1},{'WalkSeconds','보행 초록불 유지 · 초',10,6,60,1},{'FlashSeconds','보행 초록불 점멸 · 초',4,2,10,1}} do
	local c=slider(roadPage,trafficFields,spec[1],spec[2],spec[3],spec[4],spec[5],spec[6],840+(i-1)*62)
	c.Traffic=true
end
local applyTraffic=button(roadPage,'ApplyTraffic','교차로 시설 적용',12,1280)
text(roadPage,'SignalOrderHint','진입로별 직진 → 좌회전 순환 · 황색 3초 · 전체 적색 1.5초. 없는 진행 방향은 건너뜁니다. 마지막은 보행 신호입니다.',12,1323,UDim2.new(1,-24,0,83),83,14)
roadPage.Size=UDim2.new(1,0,0,1430)
text(lanePage,'LaneHelp','도로를 선택하고 진입로를 고르세요. 차로 번호는 운전자 기준 중앙선 쪽부터입니다.',12,0,UDim2.new(1,-24,0,54),54,15)
local pickApproach=button(lanePage,'PickApproach','진입로 표시 · 번호 클릭',12,64)
local focusApproach=button(lanePage,'FocusApproach','선택 진입로 위에서 보기',12,105)
local previousApproach=button(lanePage,'PreviousApproach','◀ 이전 진입로',12,147,UDim2.new(.5,-18,0,33))
local nextApproach=button(lanePage,'NextApproach','다음 진입로 ▶',0,147,UDim2.new(.5,-18,0,33));nextApproach.Position=UDim2.new(.5,6,0,147)
local laneContext=text(lanePage,'LaneContext','교차로 다시 계산 후 진입로를 선택하세요.',12,190,UDim2.new(1,-24,0,68),68,15)
local laneRows={}
for lane=1,3 do
	local title=text(lanePage,'LaneTitle'..lane,lane..'차로',12,273+(lane-1)*100)
	local controls={Title=title,Buttons={}}
	for i,spec in {{2,'좌회전'},{1,'직진'},{4,'우회전'}} do
		local b=button(lanePage,'Lane'..lane..'Direction'..spec[1],spec[2],12,305+(lane-1)*100,UDim2.new(1/3,-16,0,35))
		b.Position=UDim2.new((i-1)/3,12,0,305+(lane-1)*100);controls.Buttons[spec[1]]=b
	end
	laneRows[lane]=controls
end
local laneInfo=text(lanePage,'LaneInfo','직진·좌회전·우회전을 조합합니다. 설정은 즉시 저장되며 차량 주행·좌회전 신호 연결은 이후 단계입니다.',12,585,UDim2.new(1,-24,0,92),92,14)
lanePage.Size=UDim2.new(1,0,0,700)
local laneEntries,laneIndex={},1
local mouse=plugin:GetMouse()
local current,mode,points,calibrationPoints,selectedIndex=nil,nil,{},{},nil
local dragPoint,busy,preview,working,handles,hover,lastPreview=nil,false,nil,nil,nil,nil,0
local function guide() return workspace:FindFirstChild('BoraMapReference') end
local function numeric(field,label)
	local value=tonumber(field.Text)
	assert(value and value==value and math.abs(value)<1e6,label..' 숫자를 확인하세요.')
	return value
end
local function refreshTraffic()
	local folder=workspace:FindFirstChild('BoraRoads')
	local values=if folder then Traffic.config(folder) else Traffic.Defaults
	for key,entry in trafficToggles do
		trafficValues[key]=values[key]; entry.Button.Text=entry.Label..(if values[key] then ' 켜짐' else ' 꺼짐')
	end
	for key,field in trafficFields do field.Text=tostring(values[key]) end
end
local function roadConfig()
	local config={}; for name in Path.Defaults do config[name]=numeric(roadFields[name],name) end
	return Path.normalize(config)
end
local function refreshMap()
	local map=guide(); if not Guides.isGuide(map) then status.Text='설치된 지도가 없습니다.'; return end
	for _,name in {'Width','Rotation'} do mapFields[name].Text=string.format('%.1f',map:GetAttribute(name)) end
	mapFields.Opacity.Text=tostring(math.floor((map:GetAttribute('Opacity') or .9)*100+.5))
	mapFields.Image.Text=map:GetAttribute('Image')
	mapFields.X.Text=string.format('%.1f',map.Root.Position.X); mapFields.Z.Text=string.format('%.1f',map.Root.Position.Z)
	visibility.Text=if map:GetAttribute('Visible') then '지도 숨기기' else '지도 표시'
	calibrationLabel.Text=if map:GetAttribute('Calibrated') then string.format('축척 설정됨 · 기준 거리 %.1fm',map:GetAttribute('CalibrationMeters')) else '현재 축척 미확정 · 실제 거리를 먼저 입력하세요.'
	local aspect=map:GetAttribute('Aspect')
	mapFields.PixelHeight.Text=tostring(math.floor(tonumber(mapFields.PixelWidth.Text)*aspect+.5))
end
local function refreshRoad()
	if not Roads.isRoad(current) or not current.Parent then return end
	for key in Path.Defaults do roadFields[key].Text=tostring(current:GetAttribute(key)) end
	if selectedIndex then
		local list=Roads.points(current); selectedIndex=math.clamp(selectedIndex,1,#list)
		roadFields.NodeHeight.Text=string.format('%.2f',list[selectedIndex].Y/Path.StudsPerMeter)
	end
end
local function transaction(label,action)
	if busy or RunService:IsRunning() then return false end
	local id=History:TryBeginRecording('BoraRoadEdit',label)
	if not id then status.Text='다른 편집이 끝난 뒤 시도하세요.'; return false end
	busy=true
	local ok,result=pcall(action)
	History:FinishRecording(id,if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	busy=false
	if not ok then status.Text=tostring(result):match('[^\n]+$') or tostring(result); warn('[BoraRoad] '..tostring(result)) end
	return ok,result
end
local function clearPreview()
	if preview then preview:Destroy(); preview=nil end
end
local function editorFolder()
	if not working then
		working=Instance.new('Folder'); working.Name,working.Archivable,working.Parent='_BoraRoadEditor',false,workspace
	end
	return working
end
local function marker(position,index,color)
	local p=Instance.new('Part'); p.Name='Point'..index
	p.Shape,p.Size,p.CFrame=Enum.PartType.Ball,Vector3.one*2,CFrame.new(position+Vector3.new(0,.4,0))
	p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,false,false,true
	p.Material,p.Color,p.Parent=Enum.Material.Neon,color,handles
	p:SetAttribute('PointIndex',index)
	return p
end
local function renderHandles(list)
	if handles then handles:Destroy() end
	handles=Instance.new('Folder'); handles.Name,handles.Parent='Handles',editorFolder()
	for i,p in list do marker(p,i,if i==selectedIndex then Color3.fromRGB(255,199,77) else Color3.fromRGB(75,223,211)) end
end
local function planePoint(y,withinMap)
	local ray=mouse.UnitRay
	if math.abs(ray.Direction.Y)<.00001 then return nil end
	local t=(y-ray.Origin.Y)/ray.Direction.Y
	if t<0 then return nil end
	local p=ray.Origin+ray.Direction*t
	if withinMap then
		local map=guide(); local q=map.Root.CFrame:PointToObjectSpace(p)
		if math.abs(q.X)>map:GetAttribute('Width')*.5 or math.abs(q.Z)>map:GetAttribute('Width')*map:GetAttribute('Aspect')*.5 then return nil end
	end
	return p
end
local function snap(p)
	return Network.snap(workspace:FindFirstChild('BoraRoads'),p,current)
end
local function showPreview(list)
	clearPreview()
	if #list<2 then return end
	local ok,geometry=pcall(function() return Roads.preview(list,roadConfig()) end)
	if ok then preview=geometry; preview.Parent=editorFolder() end
end
local function stop()
	dragPoint=nil; mode=nil; points={}; calibrationPoints={}; hover=nil
	clearPreview(); if working then working:Destroy(); working,handles=nil,nil end
	plugin:Deactivate()
end
leaveLaneMode=function() if mode=='lanes' then stop() end end
local function editCurrent()
	if RunService:IsRunning() then return end
	if not current or not current.Parent then status.Text='편집할 도로를 먼저 선택하세요.'; return end
	mode='edit'; plugin:Activate(true); showTab(true)
	selectedIndex=math.clamp(selectedIndex or 1,1,#Roads.points(current))
	renderHandles(Roads.points(current)); refreshRoad()
	status.Text='빛나는 점을 드래그하세요. 높이는 선택 점 높이에서 바꿉니다.'
end
local function selectedRoad()
	local items=Selection:Get(); if #items~=1 then return nil end
	local item=items[1]
	while item and item~=workspace do
		if Roads.isRoad(item) then return item end
		if item:GetAttribute('AssetKind')=='BoraRoadJunction' then
			local ref=item:FindFirstChild('Branch'); if ref and Roads.isRoad(ref.Value) then return ref.Value end
		end
		item=item.Parent
	end
	return nil
end
local function renderLaneMarkers()
	if handles then handles:Destroy() end
	handles=Instance.new('Folder');handles.Name,handles.Parent='LaneApproaches',editorFolder()
	for i,entry in laneEntries do
		local p=marker(entry.Position,i,if i==laneIndex then Color3.fromRGB(255,199,77) else Color3.fromRGB(75,223,211))
		p:SetAttribute('ApproachIndex',i)
		local gui=Instance.new('BillboardGui');gui.Size,gui.StudsOffset,gui.AlwaysOnTop,gui.Parent=UDim2.fromOffset(72,32),Vector3.new(0,3,0),true,p
		local label=text(gui,'Number',tostring(i),0,0,UDim2.fromScale(1,1),32,23);label.TextXAlignment=Enum.TextXAlignment.Center
	end
end
refreshLanes=function()
	local selected=laneEntries[laneIndex]
	laneEntries=Lanes.entries(workspace:FindFirstChild('BoraRoads'),if current and current.Parent then current else nil)
	laneIndex=math.clamp(laneIndex,1,math.max(1,#laneEntries))
	if selected then for i,entry in laneEntries do if entry.Key==selected.Key and entry.Road==selected.Road and entry.Sign==selected.Sign then laneIndex=i;break end end end
	local entry=laneEntries[laneIndex]
	laneContext.Text=if entry then string.format('진입로 %d / %d · %s\n교차로 %s · %s에서 진입 · %d차로',laneIndex,#laneEntries,entry.Road.Name,entry.Key,if entry.Sign==-1 then '도로 시작점 쪽' else '도로 끝점 쪽',entry.Count) else '도로를 선택한 뒤 교차로 다시 계산을 눌러주세요.'
	for lane,row in laneRows do
		local visible=entry~=nil and lane<=entry.Count
		row.Title.Visible=visible
		if visible then row.Title.Text=lane..'차로 · '..Lanes.label(entry.Masks[lane]) end
		for bit,b in row.Buttons do
			b.Visible=visible
			local available=visible and bit32.band(entry.Available,bit)~=0
			b.Active,b.AutoButtonColor=available,available
			b.TextColor3=if available then Color3.fromRGB(240,244,238) else Color3.fromRGB(125,131,135)
			b.BackgroundColor3=if not available then Color3.fromRGB(49,53,59) elseif bit32.band(entry.Masks[lane],bit)~=0 then Color3.fromRGB(65,140,106) else Color3.fromRGB(65,73,80)
		end
	end
	laneInfo.Text=if entry and not entry.ArrowVisible then '이 진입로는 공간이 좁아 화살표를 생략했습니다. 방향 설정은 저장됩니다. 회색 버튼 방향에는 연결 도로가 없습니다.' else '초록 버튼이 허용 방향입니다. 복수 선택 가능 · 회색 버튼 방향에는 연결 도로가 없습니다. 차량 주행·좌회전 신호 연결은 이후 단계입니다.'
	if mode=='lanes' then renderLaneMarkers() end
end
local function finishRoad()
	if mode~='draw' then return end
	local junctionStats
	local ok,road=transaction('도로 그리기',function()
		local created=Roads.create(points,roadConfig(),Http:GenerateGUID(false))
		local folder=workspace:FindFirstChild('BoraRoads')
		if folder then assert(folder:IsA('Folder'),'BoraRoads 이름이 이미 사용 중입니다.')
		else folder=Instance.new('Folder'); folder.Name,folder.Parent='BoraRoads',workspace end
		created.Parent=folder
		local ok,err=pcall(function() local _,stats=Network.edit(folder,created,points,roadConfig(),true); junctionStats=stats end)
		if not ok then created:Destroy(); error(err) end
		return created
	end)
	if ok then
		clearPreview(); points={}; current=road; selectedIndex=1
		Selection:Set({road}); editCurrent()
		status.Text=string.format('도로 생성 완료 · %.1fm · T자 %d / 십자 %d%s',road:GetAttribute('LengthMeters'),junctionStats.T,junctionStats.Cross,if junctionStats.Limited>0 then ' · 표시 공간 부족 '..junctionStats.Limited..'방향' else '')
		print('[BoraRoad] created '..road:GetAttribute('ObjectId'))
	end
end
local function applyRoadSettings()
	if mode=='draw' then showPreview(points); return end
	if not current or not current.Parent then status.Text='새 도로에 사용할 설정입니다. 새 도로 그리기를 누르세요.'; return end
	local ok=transaction('도로 설정 변경',function() Network.edit(current.Parent,current,Roads.points(current),roadConfig(),false) end)
	if ok then refreshRoad(); if mode=='edit' then renderHandles(Roads.points(current)) end; status.Text='도로 설정을 적용했습니다.' end
end
local function applyMapSettings()
	local ok=transaction('지도 설정 변경',function()
		local map=assert(guide(),'지도가 없습니다.')
		local width,rotation,opacity=numeric(mapFields.Width,'지도 폭'),numeric(mapFields.Rotation,'회전'),numeric(mapFields.Opacity,'진하기')/100
		local x,z=numeric(mapFields.X,'X'),numeric(mapFields.Z,'Z')
		local pw,ph=numeric(mapFields.PixelWidth,'가로 픽셀'),numeric(mapFields.PixelHeight,'세로 픽셀')
		assert(pw>0 and ph>0 and ph/pw>=.1 and ph/pw<=10,'이미지 크기를 확인하세요.')
		local image=mapFields.Image.Text
		if tonumber(image) then image='rbxassetid://'..image end
		assert(image:match('^rbxasset') and #image<500,'Roblox 이미지 ID 또는 설치된 로컬 에셋 주소를 입력하세요.')
		map:SetAttribute('Image',image); map:SetAttribute('Aspect',ph/pw)
		local move=Vector3.new(x,map.Root.Position.Y,z)-map.Root.Position
		map.Root.CFrame+=move
		Guides.update(map,width,rotation,opacity)
	end)
	if ok then refreshMap(); status.Text='지도 설정 완료. 실제 거리 두 점으로 축척을 맞추세요.' end
end
local function applyTrafficSettings()
	local folder=workspace:FindFirstChild('BoraRoads')
	if not folder then status.Text='도로를 먼저 그리세요.'; return end
	local ok=transaction('교차로 시설 변경',function()
		local settings=table.clone(trafficValues)
		for key,field in trafficFields do settings[key]=numeric(field,key) end
		local _,stats=Network.apply(folder,nil,nil,nil,nil,settings); return stats
	end)
	refreshTraffic()
	if ok then
		local limited=0; for _,junction in folder.Junctions:GetChildren() do limited+=junction:GetAttribute('LimitedApproaches') or 0 end
		status.Text=if limited>0 then '시설 갱신 완료 · '..limited..'방향은 공간 부족으로 노면 표시 생략. 간격을 줄이거나 도로를 늘리세요.' else '교차로의 횡단보도·정지선·신호등을 갱신했습니다.'
	end
end
local function updateSlider()
	if not activeSlider then return end
	local c=activeSlider
	local ratio=DockPointer.ratio(widget,c.Track)
	if not ratio then return end
	local value=math.floor((c.Min+(c.Max-c.Min)*ratio)/c.Step+.5)*c.Step
	c.Input.Text=string.format(if c.Step<.1 then '%.2f' elseif c.Step<1 then '%.1f' else '%.0f',math.clamp(value,c.Min,c.Max))
end
local function finishSlider(commit)
	local control=activeSlider; activeSlider=nil
	if not control then return end
	control.Watch.Disconnect()
	if not control.Traffic and control.Page~=mapPage and control.Owner~=current then return end
	if not commit then control.Input.Text=control.Original; return end
	if control.Input.Text~=control.Original then
		if control.Traffic then applyTrafficSettings() elseif control.Page==mapPage then applyMapSettings() else applyRoadSettings() end
	end
end
for _,control in sliders do
	control.Track.InputBegan:Connect(function(input)
		if input.KeyCode==Enum.KeyCode.Escape then finishSlider(false);return end
		if busy or RunService:IsRunning() or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
		finishSlider(false)
		control.Original,control.Owner=control.Input.Text,current;activeSlider=control
		control.Watch=DockPointer.watch(control.Track,input,function(commit)
			commit=commit and widget.Enabled and not RunService:IsRunning()
			if commit then updateSlider() end;finishSlider(commit)
		end)
		updateSlider()
	end)
end
local function finishPoint(commit)
	local drag=dragPoint; dragPoint=nil
	if not drag then return end
	clearPreview()
	if commit and drag.Moved then
		local ok=transaction('도로 점 이동',function() Network.edit(current.Parent,current,drag.Points,Roads.config(current),true) end)
		if ok then status.Text='도로 점을 이동했습니다.' end
	end
	if current and current.Parent then renderHandles(Roads.points(current)); refreshRoad() end
end
topButton.Activated:Connect(function()
	local map=guide(); if not map then return end
	local camera=workspace.CurrentCamera
	local center=map.Root.Position
	camera.CFrame=CFrame.fromMatrix(center+Vector3.new(0,map:GetAttribute('Width')*.7,0),-Vector3.xAxis,Vector3.zAxis,Vector3.yAxis)
	camera.Focus=CFrame.new(center)
end)
visibility.Activated:Connect(function()
	local ok=transaction('지도 표시 변경',function() local map=assert(guide()); Guides.visible(map,not map:GetAttribute('Visible')) end)
	if ok then refreshMap() end
end)
applyMap.Activated:Connect(applyMapSettings)
applyRoad.Activated:Connect(applyRoadSettings)
pickApproach.Activated:Connect(function()
	if busy or RunService:IsRunning() then return end
	current=selectedRoad() or current;stop();showLaneTab()
	local folder=workspace:FindFirstChild('BoraRoads');if not folder then status.Text='도로와 교차로를 먼저 만드세요.';return end
	if #laneEntries==0 then
		local ok=transaction('차로 편집 준비',function() Network.apply(folder) end)
		if not ok then return end;refreshLanes()
	end
	if #laneEntries==0 then status.Text='선택한 도로에는 연결된 교차로가 없습니다.';return end
	mode='lanes';plugin:Activate(true);renderLaneMarkers()
	status.Text='빛나는 진입로 번호를 클릭하거나 이전·다음 버튼으로 고르세요.'
end)
for delta,b in {[-1]=previousApproach,[1]=nextApproach} do b.Activated:Connect(function()
	if #laneEntries==0 then refreshLanes();return end
	laneIndex=((laneIndex-1+delta)%#laneEntries)+1;refreshLanes()
end) end
focusApproach.Activated:Connect(function()
	local entry=laneEntries[laneIndex];if not entry then status.Text='진입로를 먼저 선택하세요.';return end
	local p=entry.Position;local camera=workspace.CurrentCamera
	local height=math.clamp((entry.Road:GetAttribute('Width') or 7)*Path.StudsPerMeter*4,80,180)
	camera.CFrame=CFrame.fromMatrix(p+Vector3.yAxis*height,-Vector3.xAxis,Vector3.zAxis,Vector3.yAxis);camera.Focus=CFrame.new(p)
end)
for lane,row in laneRows do for bit,b in row.Buttons do b.Activated:Connect(function()
	local entry=laneEntries[laneIndex];if not entry or lane>entry.Count then return end
	local mask=bit32.bxor(entry.Masks[lane],bit)
	local ok=transaction('차로 진행 방향 변경',function() Network.setLane(entry.Road.Parent,entry.Junction,entry.Road,entry.Sign,lane,mask) end)
	refreshLanes()
	if ok then status.Text=lane..'차로 · '..Lanes.label(mask)..' 방향을 저장했습니다.' end
end) end end
applyTraffic.Activated:Connect(applyTrafficSettings)
for key,entry in trafficToggles do entry.Button.Activated:Connect(function()
	trafficValues[key]=not trafficValues[key]; applyTrafficSettings()
end) end
calibrate.Activated:Connect(function()
	if busy or RunService:IsRunning() then return end
	stop(); widget.Enabled=true; mode='calibrate'; calibrationPoints={}; plugin:Activate(true)
	status.Text='지도에서 실제 거리를 아는 첫 번째 기준점을 클릭하세요.'
end)
drawButton.Activated:Connect(function()
	if busy or RunService:IsRunning() then return end
	stop(); current=nil; selectedIndex=nil; mode='draw'; points={}; plugin:Activate(true)
	status.Text='시작점을 클릭하세요. 이어서 점을 찍고 Enter로 확정합니다.'
end)
finishButton.Activated:Connect(finishRoad)
editButton.Activated:Connect(function() current=selectedRoad() or current; editCurrent() end)
cancelButton.Activated:Connect(function() finishSlider(false); finishPoint(false); stop(); status.Text='작업을 취소했습니다.' end)
for i,preset in presets do preset.Activated:Connect(function()
	local config=({{Width=4,Lanes=1,Sidewalk=0},{Width=7,Lanes=2,Sidewalk=1.5},{Width=14,Lanes=4,Sidewalk=2}})[i]
	for key,value in config do roadFields[key].Text=tostring(value) end
	applyRoadSettings()
end) end
heightButton.Activated:Connect(function()
	if not current or not selectedIndex then status.Text='점 편집에서 점 하나를 선택하세요.'; return end
	local ok=transaction('도로 점 높이 변경',function()
		local list=Roads.points(current); local p=list[selectedIndex]
		list[selectedIndex]=Vector3.new(p.X,numeric(roadFields.NodeHeight,'높이')*Path.StudsPerMeter,p.Z)
		Network.edit(current.Parent,current,list,roadConfig(),false)
	end)
	if ok then editCurrent() end
end)
insertButton.Activated:Connect(function()
	if not current then status.Text='도로를 먼저 선택하세요.'; return end
	mode='insert'; plugin:Activate(true); status.Text='점이 필요한 도로 구간 위를 클릭하세요.'
end)
removeButton.Activated:Connect(function()
	if not current or not selectedIndex then status.Text='점 하나를 선택하세요.'; return end
	local ok=transaction('도로 점 삭제',function()
		local list=Roads.points(current); assert(#list>2,'도로에는 최소 두 점이 필요합니다.')
		table.remove(list,selectedIndex); Network.edit(current.Parent,current,list,Roads.config(current),false)
	end)
	if ok then selectedIndex=1; editCurrent() end
end)
mouse.Button1Down:Connect(function()
	if busy or not mode then return end
	if mode=='lanes' then
		if not handles then return end
		local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Include;params.FilterDescendantsInstances={handles}
		local ray=mouse.UnitRay;local hit=workspace:Raycast(ray.Origin,ray.Direction*30000,params)
		local index=hit and hit.Instance:GetAttribute('ApproachIndex')
		if index then laneIndex=index;refreshLanes() end
		return
	end
	if mode=='edit' and handles then
		local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Include; params.FilterDescendantsInstances={handles}
		local ray=mouse.UnitRay; local hit=workspace:Raycast(ray.Origin,ray.Direction*30000,params)
		if hit then
			selectedIndex=hit.Instance:GetAttribute('PointIndex')
			dragPoint={Points=Roads.points(current),Moved=false}
			dragPoint.Y=dragPoint.Points[selectedIndex].Y
			refreshRoad()
		end
		return
	end
	local map=guide(); local p=planePoint(if map then map.Root.Position.Y else 0,mode=='calibrate')
	if not p then return end
	if mode=='draw' then
		p=snap(p)
		if #points>0 and (p-points[#points]).Magnitude<1 then return end
		table.insert(points,p); selectedIndex=nil; renderHandles(points); showPreview(points)
		status.Text=string.format('점 %d개 · 계속 클릭하거나 Enter로 확정하세요.',#points)
	elseif mode=='calibrate' then
		table.insert(calibrationPoints,p); renderHandles(calibrationPoints)
		if #calibrationPoints==1 then status.Text='두 번째 기준점을 클릭하세요.'
		else
			local ok=transaction('지도 실제 거리 축척',function() Guides.calibrate(map,calibrationPoints[1],calibrationPoints[2],numeric(mapFields.Distance,'실제 거리')) end)
			stop(); refreshMap()
			if ok then status.Text='지도 축척을 맞췄습니다. 도로 그리기를 시작하세요.' end
		end
	elseif mode=='insert' then
		local ok=transaction('도로 점 추가',function()
			local list=Roads.points(current); local index,distance=Path.closest(list,p)
			assert(distance<100,'선택한 도로 가까이를 클릭하세요.')
			local a,b=list[index],list[index+1]; local t=math.clamp((p-a):Dot(b-a)/(b-a):Dot(b-a),.02,.98)
			p=Vector3.new(p.X,a.Y+(b.Y-a.Y)*t,p.Z)
			table.insert(list,index+1,p); Network.edit(current.Parent,current,list,Roads.config(current),false); selectedIndex=index+1
		end)
		if ok then editCurrent() end
	end
end)
mouse.Move:Connect(function()
	if not mode or busy then return end
	local map=guide()
	local p=planePoint(if dragPoint then dragPoint.Y elseif map then map.Root.Position.Y else 0,false)
	if not p then return end
	if dragPoint then
		dragPoint.Points[selectedIndex]=snap(p); dragPoint.Moved=true
		local handle=handles and handles:FindFirstChild('Point'..selectedIndex)
		if handle then handle.CFrame=CFrame.new(dragPoint.Points[selectedIndex]+Vector3.new(0,.4,0)) end
	elseif mode=='draw' then hover=snap(p) end
	if os.clock()-lastPreview>.12 then
		lastPreview=os.clock()
		if dragPoint then showPreview(dragPoint.Points)
		elseif mode=='draw' and #points>0 and (p-points[#points]).Magnitude>1 then local list=table.clone(points); table.insert(list,hover); showPreview(list) end
	end
end)
mouse.Button1Up:Connect(function() finishPoint(true) end)
Input.InputEnded:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 then finishPoint(true) end
end)
Input.InputBegan:Connect(function(input)
	if Input:GetFocusedTextBox() or busy or not widget.Enabled then return end
	if input.KeyCode==Enum.KeyCode.Return then finishRoad()
	elseif input.KeyCode==Enum.KeyCode.Escape then finishSlider(false); finishPoint(false); stop()
	elseif input.KeyCode==Enum.KeyCode.Backspace and mode=='draw' then table.remove(points); renderHandles(points); showPreview(points) end
end)
RunService.Heartbeat:Connect(function()
	if RunService:IsRunning() then finishSlider(false);if mode or working then finishPoint(false); stop() end; return end
	if activeSlider then
		if not widget.Enabled or (not activeSlider.Traffic and activeSlider.Page~=mapPage and activeSlider.Owner~=current) then finishSlider(false)
		elseif not activeSlider.Watch.Poll() then updateSlider() end
	end
	if dragPoint and not Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then finishPoint(true) end
	if handles then
		for _,part in handles:GetChildren() do
			local size=math.clamp((workspace.CurrentCamera.CFrame.Position-part.Position).Magnitude*.013,1,16)
			part.Size=Vector3.one*size
		end
	end
end)
local function inspect()
	if busy or dragPoint then return end
	local road=selectedRoad()
	if road then
		current=road;widget.Enabled=true
		if lanePage.Visible then refreshLanes() else showTab(true);refreshRoad();if mode=='edit' then editCurrent() end end
	elseif current and not current.Parent then current=nil; stop() end
end
Selection.SelectionChanged:Connect(inspect)
for _,event in {History.OnUndo,History.OnRedo} do event:Connect(function()
	refreshMap(); inspect(); refreshRoad(); refreshTraffic();refreshLanes()
	if mode=='edit' and current and current.Parent then renderHandles(Roads.points(current)) end
end) end
widget.WindowFocusReleased:Connect(function() finishSlider(false) end)
widget:BindToClose(function() finishSlider(false); finishPoint(false); stop(); widget.Enabled=false end)
plugin.Deactivation:Connect(function()
	dragPoint=nil; mode=nil; clearPreview(); if working then working:Destroy(); working,handles=nil,nil end
end)
plugin.Unloading:Connect(function() finishSlider(false); stop(); widget:Destroy() end)
openButton.Click:Connect(function() widget.Enabled=not widget.Enabled; if widget.Enabled then refreshMap(); inspect() else stop() end end)
refreshNetwork.Activated:Connect(function()
	local folder=workspace:FindFirstChild('BoraRoads'); if not folder then status.Text='도로를 먼저 그리세요.'; return end
	local ok,stats=transaction('교차로 다시 계산',function() local _,result=Network.apply(folder); return result end)
	if ok then status.Text=string.format('교차로 갱신 완료 · T자 %d / 십자 %d%s',stats.T,stats.Cross,if stats.LimitedArrows>0 then ' · 화살표 공간 부족 '..stats.LimitedArrows..'방향' elseif stats.Limited>0 then ' · 표시 공간 부족 '..stats.Limited..'방향' else '');refreshLanes();if mode=='edit' then editCurrent() end end
end)
local existingMap=guide()
if Guides.isGuide(existingMap) and existingMap:GetAttribute('DisplayVersion')~=6 then
	transaction('지도 표시 방식 갱신',function()
		Guides.update(existingMap,existingMap:GetAttribute('Width'),existingMap:GetAttribute('Rotation'),existingMap:GetAttribute('Opacity'))
	end)
end
refreshMap()
refreshTraffic()
print('[BoraRoad] v0.7.1 ready: dock sliders / protected arrows / pedestrian clearance')
