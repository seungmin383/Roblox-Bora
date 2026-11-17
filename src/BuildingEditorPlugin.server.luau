if not plugin or game:GetService('RunService'):IsRunning() then return end
local Selection=game:GetService('Selection')
local History=game:GetService('ChangeHistoryService')
local Input=game:GetService('UserInputService')
local DockPointer=require(script.Parent.DockPointer)
local Run=game:GetService('RunService')
local Http=game:GetService('HttpService')
local P=require(script.Parent.BuildingParameters)
local api={Instance=Instance,Vector3=Vector3,Vector2=Vector2,CFrame=CFrame,Color3=Color3,Enum=Enum,UDim=UDim,UDim2=UDim2}
local B=require(script.Parent.BuildingPlan)({Decode=function(text) return Http:JSONDecode(text) end,Encode=function(value) return Http:JSONEncode(value) end})
local Interior=require(script.Parent.BuildingInteriorFactory)(api,B)
local F=require(script.Parent.BuildingFactory)(api,P,script.Parent:FindFirstChild('Decorations'),B,Interior)
local toolbar=plugin:CreateToolbar('보라동 건물')
local placeButton=toolbar:CreateButton('BoraBuildingPlace_v1','지면을 클릭해서 설정한 건물을 설치합니다.','','건물 설치')
local editButton=toolbar:CreateButton('BoraBuildingEdit_v1','선택한 건물의 층수·간판·외관을 편집합니다.','','건물 편집')
local planButton=toolbar:CreateButton('BoraBuildingPlan_v1','층별 도면에서 벽·계단·엘리베이터를 배치합니다.','','층별 도면')
planButton.ClickableWhenViewportHidden=true
placeButton.ClickableWhenViewportHidden,editButton.ClickableWhenViewportHidden=true,true
local widget=plugin:CreateDockWidgetPluginGuiAsync('BoraBuildingInspector_v1',DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,false,true,410,860,375,550))
widget.Title='건물 인스펙터'
local bg=Instance.new('ScrollingFrame');bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=Color3.fromRGB(30,34,40)
bg.BorderSizePixel,bg.ScrollBarThickness,bg.CanvasSize=0,6,UDim2.fromOffset(0,1165);bg.Parent=widget
local function label(text,y,height)
	local o=Instance.new('TextLabel');o.Text,o.Position,o.Size=text,UDim2.fromOffset(16,y),UDim2.new(1,-32,0,height or 24)
	o.BackgroundTransparency,o.TextColor3,o.TextSize=1,Color3.fromRGB(230,235,237),15
	o.Font,o.TextXAlignment,o.TextWrapped=Enum.Font.SourceSans,Enum.TextXAlignment.Left,true;o.Parent=bg;return o
end
local function button(text,y)
	local o=Instance.new('TextButton');o.Text,o.Position,o.Size=text,UDim2.fromOffset(16,y),UDim2.new(1,-32,0,34)
	o.BackgroundColor3,o.TextColor3,o.Font,o.TextSize=Color3.fromRGB(66,91,87),Color3.new(1,1,1),Enum.Font.SourceSansBold,16;o.Parent=bg;return o
end
local function box(text,position,size)
	local o=Instance.new('TextBox');o.Text,o.Position,o.Size=text,position,size
	o.ClearTextOnFocus,o.BackgroundColor3,o.TextColor3=false,Color3.fromRGB(49,56,65),Color3.fromRGB(243,240,229)
	o.Font,o.TextSize,o.Parent=Enum.Font.SourceSans,17,bg;return o
end
label('종류와 층을 조합하는 건물',12,30).TextSize=23
local selected=label('건물 선택 또는 새 건물 설치',48,32)
local kind='Shop';local kinds={};local values={};local toggles={};local sliders={}
for i,name in P.Kinds do
	local o=button(P.KindLabels[i],90+math.floor((i-1)/4)*37)
	o.Position,o.Size=UDim2.new(((i-1)%4)*.25,16-((i-1)%4)*4,0,90+math.floor((i-1)/4)*37),UDim2.new(.25,-8,0,31)
	kinds[name]=o;o.MouseButton1Click:Connect(function() kind=name;for k,b in kinds do b.BackgroundColor3=if k==kind then Color3.fromRGB(88,140,112) else Color3.fromRGB(49,56,65) end end)
end
label('간판 이름 · 최대 48자',168)
values.Title=box('보라 상가',UDim2.fromOffset(16,195),UDim2.new(1,-32,0,32))
local function paint(key,n)
	local bar=sliders[key];local ratio=math.clamp((n-bar.Min)/(bar.Max-bar.Min),0,1)
	bar.Fill.Size,bar.Knob.Position=UDim2.fromScale(ratio,1),UDim2.fromScale(ratio,.5)
end
for i,spec in P.Numbers do
	local y=240+(i-1)*61;label(spec[2]..'  '..spec[4]..'~'..spec[5],y)
	values[spec[1]]=box(tostring(spec[3]),UDim2.new(1,-98,0,y),UDim2.fromOffset(80,26))
	local bar=button('',y+31);bar.Size=UDim2.new(1,-32,0,16);bar.AutoButtonColor=false;bar.BackgroundColor3=Color3.fromRGB(65,73,80)
	local fill=Instance.new('Frame');fill.BackgroundColor3,fill.BorderSizePixel,fill.Parent=Color3.fromRGB(108,154,129),0,bar
	local knob=Instance.new('Frame');knob.Size,knob.AnchorPoint,knob.Parent=UDim2.fromOffset(6,24),Vector2.new(.5,.5),bar
	knob.BackgroundColor3,knob.BorderSizePixel=Color3.fromRGB(219,239,224),0
	sliders[spec[1]]={Track=bar,Fill=fill,Knob=knob,Min=spec[4],Max=spec[5],Step=spec[6]};paint(spec[1],spec[3])
	values[spec[1]]:GetPropertyChangedSignal('Text'):Connect(function() local n=tonumber(values[spec[1]].Text);if n and n==n and math.abs(n)<math.huge then paint(spec[1],n) end end)
end
local optionNames={Sign='간판',Balconies='발코니',Awning='차양',Details='벽등·옥상 장식'}
for i,key in {'Sign','Balconies','Awning','Details'} do
	local o=button('',672+(i-1)*35);toggles[key]={Button=o,Value=P.Defaults[key]}
	o.MouseButton1Click:Connect(function() local t=toggles[key];t.Value=not t.Value;o.Text=optionNames[key]..'  '..(if t.Value then '켜짐' else '꺼짐') end)
end
for i,spec in {{'Wall','외벽 색'},{'Trim','띠·창턱 색'},{'Accent','창틀·간판 색'}} do
	label(spec[2]..' · HEX',817+(i-1)*35)
	values[spec[1]]=box(P.Defaults[spec[1]],UDim2.new(1,-130,0,817+(i-1)*35),UDim2.fromOffset(112,28))
end
label('새 건물 방향 · 도 (0~359)',926)
local rotation=box('0',UDim2.new(1,-98,0,926),UDim2.fromOffset(80,28))
local openPlan=button('층별 도면 · 벽 / 계단 / 엘리베이터',968)
local apply=button('선택한 건물에 적용',1010)
local status=label('슬라이더는 놓을 때 적용됩니다. 직접 추가한 소품은 Geometry 밖에 두세요. 생성 부품의 수동 수정은 적용 시 다시 제작됩니다.',1054,88)
local current,busy,placing,marker,drag=nil,false,false,nil,nil
local retired={};local mouse=plugin:GetMouse();local S=1/.28
local planEditor=nil
local function message(text) status.Text=text end
local function read()
	local p={Kind=kind};for k,field in values do
		if sliders[k] then local n=tonumber(field.Text);assert(n,'올바른 숫자를 입력하세요: '..k);p[k]=n else p[k]=field.Text end
	end
	for k,t in toggles do p[k]=t.Value end
	p.PlanJSON=if current and current.Parent then current:GetAttribute('BB_PlanJSON') or '' else ''
	return P.normalize(p)
end
local function refresh(config)
	local p=config or (if current and current.Parent then P.read(current) else P.normalize())
	kind=p.Kind;for k,b in kinds do b.BackgroundColor3=if k==kind then Color3.fromRGB(88,140,112) else Color3.fromRGB(49,56,65) end
	for k,field in values do field.Text=if type(p[k])=='number' then string.format('%g',p[k]) else p[k] end
	for k,t in toggles do t.Value=p[k];t.Button.Text=optionNames[k]..'  '..(if p[k] then '켜짐' else '꺼짐') end
	selected.Text=if current and current.Parent then '선택: '..current.Name else '새 건물 설정 · 지면 클릭으로 설치'
	if planEditor then planEditor.Refresh() end
end
local function inspect()
	if busy or placing then return end
	local items=Selection:Get();current=nil
	if #items==1 then local m=items[1];while m and m~=workspace do if F.isBuilding(m) then current=m;break end;m=m.Parent end end
	if current then widget.Enabled=true;refresh() else selected.Text='건물을 하나 선택하세요 · 새 건물 설치 가능';if planEditor then planEditor.Refresh() end end
end
local function checkSpace(p,base,ignore)
	local h=p.GroundHeight+(p.Floors-1)*p.FloorHeight
	local query=OverlapParams.new();query.FilterType=Enum.RaycastFilterType.Exclude
	local excluded={};if ignore then table.insert(excluded,ignore) end;if marker then table.insert(excluded,marker) end
	query.FilterDescendantsInstances=excluded
	for _,hit in workspace:GetPartBoundsInBox(base*CFrame.new(0,(h*.5+.4)*S,0),Vector3.new(p.Width-.10,h-.3,p.Depth-.10)*S,query) do
		if hit.CanCollide then error('다른 물체와 겹칩니다: '..hit.Name..' · 크기나 위치를 조절하세요.') end
	end
	local roads=workspace:FindFirstChild('BoraRoads');if not roads then return end
	local asphalt={};for _,item in roads:GetDescendants() do if item.Name=='Asphalt' then table.insert(asphalt,item) end end
	if #asphalt==0 then return end
	query.FilterType=Enum.RaycastFilterType.Include;query.FilterDescendantsInstances=asphalt
	local hits=workspace:GetPartBoundsInBox(base*CFrame.new(0,-.05*S,-p.Apron*.5*S),Vector3.new(p.Width+.7,.65,p.Depth+p.Apron)*S,query)
	assert(#hits==0,'건물 또는 앞마당이 차도와 겹칩니다. 크기·앞마당 깊이를 줄이세요.')
end
local function ensureRuntime()
	local server=game:GetService('ServerScriptService');local scripts=game:GetService('StarterPlayer'):FindFirstChildOfClass('StarterPlayerScripts')
	assert(scripts,'StarterPlayerScripts가 필요합니다.')
	for _,spec in {{server,'BoraBuildingRuntime','RuntimeTemplate'},{scripts,'BoraBuildingClient','ClientTemplate'}} do
		local old=spec[1]:FindFirstChild(spec[2]);assert(not old or old:GetAttribute('BoraOwned')==true,'건물 런타임 이름이 사용 중입니다.')
	end
	for _,spec in {{server,'BoraBuildingRuntime','RuntimeTemplate'},{scripts,'BoraBuildingClient','ClientTemplate'}} do
		local old=spec[1]:FindFirstChild(spec[2]);local template=script.Parent[spec[3]]
		if not old then old=template:Clone();old.Name=spec[2];old.Disabled=false;old.Parent=spec[1]
		elseif old:GetAttribute('BuildingVersion')~=F.Version then
			old.Source=template.Source
			for _,child in template:GetChildren() do local existing=old:FindFirstChild(child.Name);if existing then existing.Source=child.Source else child:Clone().Parent=old end end
		end
		old:SetAttribute('BoraOwned',true);old:SetAttribute('BuildingVersion',F.Version)
	end
end
local function applyConfig(override,planOnly)
	if busy or Run:IsRunning() then return end
	if not current or not current.Parent then message('먼저 보라 건물을 하나 선택하세요.');return false,'건물을 선택하세요.' end
	local valid,p=pcall(function() local config=if type(override)=='table' then P.normalize(override) else read();B.decode(config.PlanJSON,config);return config end)
	if not valid then message(tostring(p));return false,tostring(p) end
	if not planOnly and not F.keepsShell(current,p) then
		local clear,err=pcall(checkSpace,p,current.BuildingOrigin.CFrame,current);if not clear then message(tostring(err));return false,tostring(err) end
	end
	local record=History:TryBeginRecording('BoraBuildingEdit','건물 설정 변경');if not record then message('다른 편집이 끝난 뒤 다시 시도하세요.');return end
	busy=true;local ok,old=pcall(function() ensureRuntime();return F.rebuild(current,p) end)
	if ok then table.insert(retired,old) end
	History:FinishRecording(record,if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	busy=false;if ok then Selection:Set({current});refresh();message('적용 완료 · Ctrl+Z로 되돌릴 수 있어요.') else message(tostring(old));warn(old) end
	return ok,if ok then nil else tostring(old)
end
apply.MouseButton1Click:Connect(applyConfig)
local function updateDrag()
	if not drag then return end
	local bar=sliders[drag.Key];local ratio=DockPointer.ratio(widget,bar.Track)
	if not ratio then return end
	local n=bar.Min+ratio*(bar.Max-bar.Min)
	values[drag.Key].Text=string.format('%g',math.floor(n/bar.Step+.5)*bar.Step)
end
local function finishDrag(commit)
	if not drag then return end
	local old=drag;drag=nil
	old.Watch.Disconnect()
	if old.Owner~=current then return end
	if not commit then values[old.Key].Text=old.Original
	elseif current and values[old.Key].Text~=old.Original then applyConfig() end
end
for key,bar in sliders do bar.Track.InputBegan:Connect(function(input)
	if input.KeyCode==Enum.KeyCode.Escape then finishDrag(false);return end
	if busy or Run:IsRunning() or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
	finishDrag(false)
	drag={Key=key,Original=values[key].Text,Owner=current}
	drag.Watch=DockPointer.watch(bar.Track,input,function(commit)
		commit=commit and widget.Enabled and not Run:IsRunning() and drag.Owner==current
		if commit then updateDrag() end;finishDrag(commit)
	end)
	updateDrag()
end) end
Run.Heartbeat:Connect(function()
	if not drag then return end
	if not widget.Enabled or Run:IsRunning() or drag.Owner~=current then finishDrag(false)
	elseif not drag.Watch.Poll() then updateDrag() end
end)
local function stop()
	placing=false;placeButton:SetActive(false);if marker then marker:Destroy();marker=nil end;plugin:Deactivate()
end
local function ground()
	local ray=mouse.UnitRay;local query=RaycastParams.new();query.FilterType=Enum.RaycastFilterType.Exclude
	query.FilterDescendantsInstances=if marker then {marker} else {}
	local hit=workspace:Raycast(ray.Origin,ray.Direction*3000,query)
	if not hit or hit.Normal.Y<.98 then return nil end
	local yaw=tonumber(rotation.Text);if not yaw or yaw~=yaw or math.abs(yaw)==math.huge then return nil end
	return CFrame.new(hit.Position)*CFrame.Angles(0,math.rad(yaw%360),0)
end
local function move()
	if not placing or not marker then return end
	local base=ground();local valid,p=pcall(read)
	if base and valid then marker.Size=Vector3.new(p.Width,.04,p.Depth)*S;marker.CFrame=base*CFrame.new(0,.03*S,0);marker.Transparency=.65 else marker.Transparency=1 end
end
placeButton.Click:Connect(function()
	if busy or Run:IsRunning() then return end
	if placing then stop();return end
	current=nil;widget.Enabled=true;placing=true;plugin:Activate(true);placeButton:SetActive(true)
	marker=Instance.new('Part');marker.Name='BoraBuildingPlacementMarker';marker.Anchored=true
	marker.CanCollide,marker.CanTouch,marker.CanQuery=false,false,false
	marker.Material,marker.Color,marker.Parent=Enum.Material.Neon,Color3.fromRGB(100,194,160),workspace
	message('지면을 클릭하면 건물 중심을 놓습니다. Esc로 취소합니다.');move()
end)
mouse.Move:Connect(move)
mouse.Button1Down:Connect(function()
	if not placing or busy or Run:IsRunning() then return end
	local base=ground();if not base then message('평평한 지면을 선택하세요.');return end
	local valid,p=pcall(read);if not valid then message(tostring(p));return end
	local clear,err=pcall(checkSpace,p,base,nil);if not clear then message(tostring(err));return end
	local record=History:TryBeginRecording('BoraBuildingPlace','건물 설치');if not record then return end
	busy=true;local ok,b=pcall(function()
		local made=F.create(p,base);local folder=workspace:FindFirstChild('BoraBuildings')
		ensureRuntime()
		if folder then assert(folder:IsA('Folder'),'BoraBuildings 이름이 사용 중입니다.') else folder=Instance.new('Folder');folder.Name,folder.Parent='BoraBuildings',workspace end
		made.Parent=folder;return made
	end)
	History:FinishRecording(record,if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	busy=false;if ok then stop();Selection:Set({b});inspect();message('건물 설치 완료 · Ctrl+Z로 취소할 수 있어요.') else message(tostring(b));warn(b) end
end)
editButton.Click:Connect(function() stop();widget.Enabled=true;inspect() end)
local function showPlan()
	if busy or Run:IsRunning() then return end
	if not current or not current.Parent then widget.Enabled=true;message('도면을 편집할 건물을 하나 선택하세요.');return end
	if not planEditor then planEditor=require(script.Parent.BuildingPlanEditor)(plugin,{Run=Run,Pointer=DockPointer},P,B,{
		Get=function() return current end,
		Apply=function(building,json)
			if building~=current then return false,'선택한 건물이 바뀌었습니다.' end
			local config=P.read(building);config.PlanJSON=json;return applyConfig(config,true)
		end,
	}) end
	planEditor.Open()
end
planButton.Click:Connect(showPlan);openPlan.MouseButton1Click:Connect(showPlan)
Selection.SelectionChanged:Connect(inspect)
History.OnUndo:Connect(inspect);History.OnRedo:Connect(inspect)
widget.WindowFocusReleased:Connect(function() finishDrag(false) end)
widget:BindToClose(function() finishDrag(false);stop();widget.Enabled=false end)
plugin.Deactivation:Connect(function() placing=false;placeButton:SetActive(false);if marker then marker:Destroy();marker=nil end end)
Input.InputBegan:Connect(function(input) if input.KeyCode==Enum.KeyCode.Escape then finishDrag(false);if placing then stop() end end end)
plugin.Unloading:Connect(function() finishDrag(false);if marker then marker:Destroy() end;if planEditor then planEditor.Destroy() end;widget:Destroy() end)
refresh(P.normalize())
print('[BoraBuilding] v'..F.Version..' ready: floor-plan pivots / doors / stairs / elevators / Undo')
