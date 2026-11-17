if not plugin then return end
local RunService=game:GetService('RunService')
if RunService:IsRunning() then return end
local Selection=game:GetService('Selection')
local History=game:GetService('ChangeHistoryService')
local UserInput=game:GetService('UserInputService')
local DockPointer=require(script.Parent.DockPointer)
local Http=game:GetService('HttpService')
local ContentProvider=game:GetService('ContentProvider')
local rules=require(script.Parent.GrowthMath)
local catalog=require(script.Parent.TreeAssetCatalog)
local Parameters=require(script.Parent.TreeParameters)
local Skeleton=require(script.Parent.TreeSkeleton)(Vector3,Parameters)
local Mesher=require(script.Parent.TreeMesher)(Vector3)
local api={Instance=Instance,Vector3=Vector3,CFrame=CFrame,Color3=Color3,Enum=Enum,UDim2=UDim2}
-- Preserve detached snapshots for Studio's undo service. Destroy() would lock
-- their hierarchy before Studio can reparent it on Undo.
local historyGeometry={}
api.RetireGeometry=function(geometry) geometry.Parent=nil; table.insert(historyGeometry,geometry) end
api.BuildWood=require(script.Parent.TreeMeshBackend)(game:GetService('AssetService'),Content,Vector3,Vector2,Color3,Enum,catalog.ProceduralBark)
local factory=require(script.Parent.ProceduralTreeFactory)(api,rules,catalog,Parameters,Skeleton,Mesher)
local legacy=require(script.Parent.GrowthTreeFactory)(api,rules,catalog)
local toolbar=plugin:CreateToolbar('보라동 나무')
local placeButton=toolbar:CreateButton('BoraTreePlace_v4','지면을 클릭해 어린 은행나무를 설치합니다','','나무 설치')
local editButton=toolbar:CreateButton('BoraTreeEdit_v4','선택한 나무의 성장과 가지 구조를 편집합니다','','나무 편집')
placeButton.ClickableWhenViewportHidden=true
local widget=plugin:CreateDockWidgetPluginGuiAsync('BoraTreeInspector_v4_sliders',DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,false,true,360,670,330,655))
widget.Title='나무 인스펙터'
local bg=Instance.new('Frame')
bg.Size,bg.BackgroundColor3,bg.BorderSizePixel,bg.Parent=UDim2.fromScale(1,1),Color3.fromRGB(30,34,40),0,widget
local function label(name,value,x,y,w,h,size)
	local item=Instance.new('TextLabel')
	item.Name,item.Text,item.Position,item.Size=name,value,UDim2.fromOffset(x,y),UDim2.new(1,w,0,h)
	item.BackgroundTransparency,item.TextColor3,item.TextSize=1,Color3.fromRGB(231,236,239),size or 16
	item.Font,item.TextXAlignment,item.TextWrapped=Enum.Font.SourceSans,Enum.TextXAlignment.Left,true
	item.Parent=bg
	return item
end
label('Title','은행나무 · 가지 생성기',20,12,-40,32,24)
label('Description','슬라이더를 끌고 놓으면 나무에 적용',20,49,-40,25,15)
local percentage=label('Percentage','성장 0%',20,88,-40,25,18)
local track=Instance.new('TextButton')
track.Name,track.Text,track.Position,track.Size='GrowthSlider','',UDim2.fromOffset(20,121),UDim2.new(1,-40,0,28)
track.BackgroundColor3,track.BorderSizePixel,track.AutoButtonColor,track.Parent=Color3.fromRGB(65,73,80),0,false,bg
local fill=Instance.new('Frame')
fill.Size,fill.BackgroundColor3,fill.BorderSizePixel,fill.Parent=UDim2.fromScale(0,1),Color3.fromRGB(190,163,100),0,track
local knob=Instance.new('Frame')
knob.Name,knob.Size,knob.AnchorPoint='Handle',UDim2.fromOffset(7,36),Vector2.new(.5,.5)
knob.Position,knob.BackgroundColor3,knob.BorderSizePixel,knob.Parent=UDim2.fromScale(0,.5),Color3.fromRGB(248,229,180),0,track
label('GrowthHint','어린 나무                                      성목',20,155,-40,25,14)
local fields,sliders={},{}
-- UI units: ratios use whole percentages. Seed has a useful drag range while
-- the number field still accepts the complete saved-recipe range.
local specs={{'BranchCount','큰 가지 수 · 4~14',9,4,14},{'Spread','가지 퍼짐 · 65~140%',100,65,140},
	{'Thickness','목재 굵기 · 65~150%',100,65,150},{'LeafDensity','잎 밀도 · 0~150%',100,0,150},{'Seed','모양 시드 · 드래그 0~999',42,0,999}}
local function paintSlider(name,value)
	local slider=sliders[name]
	local ratio=math.clamp((value-slider.Min)/(slider.Max-slider.Min),0,1)
	slider.Fill.Size,slider.Knob.Position=UDim2.fromScale(ratio,1),UDim2.fromScale(ratio,.5)
end
for i,spec in specs do
	local y=188+(i-1)*65
	label(spec[1]..'Label',spec[2],20,y,-130,32,16)
	local input=Instance.new('TextBox')
	input.Name,input.Text,input.ClearTextOnFocus=spec[1]..'Input',tostring(spec[3]),false
	input.Position,input.Size=UDim2.new(1,-99,0,y),UDim2.fromOffset(79,32)
	input.BackgroundColor3,input.TextColor3=Color3.fromRGB(49,56,65),Color3.fromRGB(240,240,230)
	input.Font,input.TextSize,input.Parent=Enum.Font.SourceSans,18,bg
	fields[spec[1]]=input
	local bar=Instance.new('TextButton')
	bar.Name,bar.Text,bar.Position,bar.Size=spec[1]..'Slider','',UDim2.fromOffset(20,y+37),UDim2.new(1,-40,0,18)
	bar.BackgroundColor3,bar.BorderSizePixel,bar.AutoButtonColor,bar.Parent=Color3.fromRGB(65,73,80),0,false,bg
	local filled=Instance.new('Frame')
	filled.BackgroundColor3,filled.BorderSizePixel,filled.Parent=Color3.fromRGB(102,157,127),0,bar
	local handle=Instance.new('Frame')
	handle.Name,handle.Size,handle.AnchorPoint='Handle',UDim2.fromOffset(7,26),Vector2.new(.5,.5)
	handle.BackgroundColor3,handle.BorderSizePixel,handle.Parent=Color3.fromRGB(212,238,220),0,bar
	sliders[spec[1]]={Track=bar,Fill=filled,Knob=handle,Min=spec[4],Max=spec[5]}
	paintSlider(spec[1],spec[3])
	input:GetPropertyChangedSignal('Text'):Connect(function()
		local value=tonumber(input.Text)
		if value and value==value and math.abs(value)<math.huge then paintSlider(spec[1],value) end
	end)
end
local apply=Instance.new('TextButton')
apply.Name,apply.Text,apply.Position,apply.Size='ApplyStructure','가지 설정 적용',UDim2.fromOffset(20,527),UDim2.new(1,-40,0,39)
apply.BackgroundColor3,apply.TextColor3=Color3.fromRGB(80,124,97),Color3.new(1,1,1)
apply.Font,apply.TextSize,apply.Parent=Enum.Font.SourceSansBold,18,bg
local status=label('Status','드래그로 조절하거나 숫자를 직접 입력하세요.',20,579,-40,68,15)
local current,busy,placing,marker,dragRecord,growthWatch,unloaded=nil,false,false,nil,nil,nil,false
local parameterDrag=nil
local applyConfig
local assetsReady=false
local mouse=plugin:GetMouse()
local function readConfig()
	local config={}
	for _,spec in specs do
		local value=tonumber(fields[spec[1]].Text)
		assert(value,'숫자를 입력하세요: '..spec[2])
		if spec[1]=='Spread' or spec[1]=='Thickness' or spec[1]=='LeafDensity' then value/=100 end
		config[spec[1]]=value
	end
	return Parameters.normalize(config)
end
local function refresh(parameters)
	if not current or not current.Parent then return end
	local g=current:GetAttribute('Growth') or 0
	percentage.Text=string.format('성장 %d%%',math.floor(g*100+.5))
	fill.Size,knob.Position=UDim2.fromScale(g,1),UDim2.fromScale(g,.5)
	if parameters then
		for _,spec in specs do
			local value=current:GetAttribute(spec[1])
			if value==nil then value=Parameters.Defaults[spec[1]] end
			if spec[1]=='Spread' or spec[1]=='Thickness' or spec[1]=='LeafDensity' then value=math.floor(value*100+.5) end
			fields[spec[1]].Text=tostring(value)
		end
	end
end
local function finishDrag(commit)
	local id=dragRecord;dragRecord=nil
	if growthWatch then growthWatch.Disconnect();growthWatch=nil end
	if id then History:FinishRecording(id,if commit then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel) end
end
local function selectedTree()
	local items=Selection:Get()
	if #items~=1 then return nil end
	local item=items[1]
	while item and item~=workspace do if factory.isTree(item) then return item end; item=item.Parent end
	return nil
end
local function inspect()
	finishDrag(false)
	if parameterDrag then parameterDrag.Watch.Disconnect() end
	parameterDrag=nil
	current=selectedTree()
	if current then
		widget.Enabled=true; refresh(true)
		status.Text=if current:GetAttribute('SchemaVersion')==4 then '가지 적용과 성장 편집은 Ctrl+Z로 되돌릴 수 있어요.' else '적용하면 현재 위치를 유지하며 새 생성기 구조로 전환합니다.'
	end
end
local function ensureRuntime()
	local server=game:GetService('ServerScriptService')
	local old=server:FindFirstChild('BoraProceduralRuntime')
	if old then
		assert(old:GetAttribute('BoraOwned')==true,'Runtime name already used')
		-- Existing saved places must use the same mesher in Play as in edit mode.
		if old:GetAttribute('GeneratorVersion')~='0.4.2' then
			old.Source=script.Parent.RuntimeTemplate.Source
			for _,name in {'GrowthMath','TreeAssetCatalog','TreeParameters','TreeSkeleton','TreeMesher','TreeMeshBackend','ProceduralTreeFactory'} do
				local existing=old:FindFirstChild(name)
				if existing then existing.Source=script.Parent[name].Source else script.Parent[name]:Clone().Parent=old end
			end
			old:SetAttribute('GeneratorVersion','0.4.2')
		end
		return
	end
	local runtime=script.Parent.RuntimeTemplate:Clone()
	runtime.Name,runtime.Disabled='BoraProceduralRuntime',false
	runtime:SetAttribute('BoraOwned',true)
	runtime:SetAttribute('GeneratorVersion','0.4.2')
	for _,name in {'GrowthMath','TreeAssetCatalog','TreeParameters','TreeSkeleton','TreeMesher','TreeMeshBackend','ProceduralTreeFactory'} do script.Parent[name]:Clone().Parent=runtime end
	runtime.Parent=server
end
local function progress(value)
	assert(not unloaded,'Plugin unloaded')
	status.Text=string.format('목재 표면 생성 중 · %d%%',math.floor(value*100))
	task.wait()
end
applyConfig=function()
	if busy or RunService:IsRunning() then return end
	if not assetsReady then status.Text='로컬 에셋을 로딩 중이거나 누락됐습니다. 설치 상태를 확인하세요.'; return end
	if not current or not current.Parent then status.Text='편집할 나무 한 그루를 선택하세요.'; return end
	finishDrag(true)
	local valid,config=pcall(readConfig)
	if not valid then status.Text='숫자와 입력 범위를 확인하세요.'; warn(config); return end
	local target=current
	local record=History:TryBeginRecording('BoraTreeStructure','나무 가지 구조 변경')
	if not record then status.Text='다른 편집이 끝난 뒤 시도하세요.'; return end
	busy,apply.Text=true,'만드는 중…'
	local started=os.clock()
	local ok,err=pcall(function() ensureRuntime(); factory.rebuild(target,config,progress) end)
	History:FinishRecording(record,if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	busy,apply.Text=false,'가지 설정 적용'
	if ok then
		refresh(true)
		status.Text=string.format('완료 · 큰 가지 %d개 · %.1f초',config.BranchCount,os.clock()-started)
		print(string.format('[BoraTree] structure applied: branches=%d triangles=%d id=%s',config.BranchCount,target:GetAttribute('WoodTriangles'),target:GetAttribute('ObjectId') or ''))
	else status.Text='생성하지 못했습니다. 기존 나무를 유지합니다.'; warn('[BoraTree] structure: '..tostring(err)) end
end
apply.Activated:Connect(applyConfig)
local function updateParameterDrag()
	if not parameterDrag or busy then return end
	local slider=sliders[parameterDrag.Name]
	local ratio=DockPointer.ratio(widget,slider.Track)
	if not ratio then return end
	local value=math.floor(slider.Min+ratio*(slider.Max-slider.Min)+.5)
	fields[parameterDrag.Name].Text=tostring(value)
	parameterDrag.Changed=value~=parameterDrag.Start
end
local function finishParameterDrag(commit)
	local drag=parameterDrag; parameterDrag=nil
	if not drag then return end
	drag.Watch.Disconnect()
	if drag.Owner~=current then return end
	if not commit then fields[drag.Name].Text=drag.Original; return end
	if drag.Changed and current and current.Parent then applyConfig() end
end
for _,spec in specs do
	local name=spec[1]
	sliders[name].Track.InputBegan:Connect(function(input)
		if input.KeyCode==Enum.KeyCode.Escape then finishParameterDrag(false);return end
		if busy or RunService:IsRunning() or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
		finishDrag(false);finishParameterDrag(false)
		parameterDrag={Name=name,Owner=current,Original=fields[name].Text,Start=tonumber(fields[name].Text),Changed=false}
		parameterDrag.Watch=DockPointer.watch(sliders[name].Track,input,function(commit)
			commit=commit and widget.Enabled and not busy and not RunService:IsRunning() and parameterDrag.Owner==current
			if commit then updateParameterDrag() end;finishParameterDrag(commit)
		end)
		updateParameterDrag()
	end)
end
local function updateDrag()
	if not dragRecord or busy or not current or not current.Parent then return end
	local value=DockPointer.ratio(widget,track)
	if not value then return end
	local ok,err=pcall(function()
		if current:GetAttribute('SchemaVersion')==4 then factory.setGrowth(current,value) else legacy.setGrowth(current,value) end
	end)
	if not ok then finishDrag(false); status.Text='성장 값을 변경하지 못했습니다.'; warn(err) end
	refresh(false)
end
track.InputBegan:Connect(function(input)
	if input.KeyCode==Enum.KeyCode.Escape then finishDrag(false);refresh(false);return end
	if busy or not current or RunService:IsRunning() or input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
	finishDrag(false)
	finishParameterDrag(false)
	dragRecord=History:TryBeginRecording('BoraTreeGrowth','나무 성장 조절')
	if dragRecord then
		local owner=current
		growthWatch=DockPointer.watch(track,input,function(commit)
			commit=commit and widget.Enabled and owner==current and not RunService:IsRunning()
			if commit then updateDrag() end
			finishDrag(commit);refresh(false)
		end)
		updateDrag()
	end
end)
widget.WindowFocusReleased:Connect(function() finishDrag(false);finishParameterDrag(false);refresh(false) end)
widget:BindToClose(function() finishDrag(false);finishParameterDrag(false);refresh(false);widget.Enabled=false end)
RunService.Heartbeat:Connect(function()
	if parameterDrag then
		if not widget.Enabled or busy or RunService:IsRunning() then finishParameterDrag(false)
		elseif not parameterDrag.Watch.Poll() then updateParameterDrag() end
	end
	if dragRecord then
		if not widget.Enabled or not current or not current.Parent or RunService:IsRunning() then finishDrag(false);refresh(false)
		elseif not growthWatch.Poll() then updateDrag() end
	end
end)
local function treeFolder()
	local folder=workspace:FindFirstChild('BoraTrees')
	if folder then assert(folder:IsA('Folder'),'BoraTrees must be a folder'); return folder end
	folder=Instance.new('Folder'); folder.Name,folder.Parent='BoraTrees',workspace; return folder
end
local function pickGround()
	local ray=mouse.UnitRay
	local parameters=RaycastParams.new()
	parameters.FilterType=Enum.RaycastFilterType.Exclude
	local excluded={}
	if marker then table.insert(excluded,marker) end
	if workspace:FindFirstChild('BoraTrees') then table.insert(excluded,workspace.BoraTrees) end
	parameters.FilterDescendantsInstances=excluded
	local hit=workspace:Raycast(ray.Origin,ray.Direction*3000,parameters)
	return if hit and hit.Normal.Y>=.65 then hit else nil
end
local function stopPlacement()
	placing=false; placeButton:SetActive(false)
	if marker then marker:Destroy(); marker=nil end
	plugin:Deactivate()
end
local function moveMarker()
	if not placing or not marker then return end
	local hit=pickGround()
	if hit then marker.CFrame=CFrame.new(hit.Position+Vector3.new(0,.05,0)); marker.Transparency=.4 else marker.Transparency=1 end
end
placeButton.Click:Connect(function()
	if busy or RunService:IsRunning() then return end
	if not assetsReady then widget.Enabled=true; status.Text='로컬 에셋을 로딩 중이거나 누락됐습니다. 설치 상태를 확인하세요.'; return end
	if placing then stopPlacement(); return end
	widget.Enabled=true
	placing=true; plugin:Activate(true); placeButton:SetActive(true)
	marker=Instance.new('Part')
	marker.Name,marker.Size,marker.Anchored='BoraTreePlacementMarker',Vector3.new(2,.08,2),true
	marker.CanCollide,marker.CanQuery,marker.CanTouch=false,false,false
	marker.Material,marker.Color,marker.Parent=Enum.Material.Neon,Color3.fromRGB(79,206,184),workspace
	moveMarker()
end)
mouse.Move:Connect(moveMarker)
mouse.Button1Down:Connect(function()
	if busy or not placing or RunService:IsRunning() then return end
	local hit=pickGround(); if not hit then return end
	local valid,config=pcall(readConfig)
	if not valid then status.Text='입력 범위를 확인하세요.'; return end
	local record=History:TryBeginRecording('BoraTreePlace','나무 설치'); if not record then return end
	busy=true
	local ok,tree=pcall(function()
		ensureRuntime()
		config.Growth,config.ObjectId=0,Http:GenerateGUID(false)
		local created=factory.create(config,CFrame.new(hit.Position),progress)
		created.Parent=treeFolder(); return created
	end)
	History:FinishRecording(record,if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	busy=false
	if ok then stopPlacement(); Selection:Set({tree}); inspect() else status.Text='설치하지 못했습니다.'; warn(tree) end
end)
editButton.Click:Connect(function() widget.Enabled=true; inspect() end)
Selection.SelectionChanged:Connect(function() if not busy then inspect() end end)
History.OnUndo:Connect(function() if current and current.Parent then refresh(true) end end)
History.OnRedo:Connect(function() if current and current.Parent then refresh(true) end end)
UserInput.InputBegan:Connect(function(input)
	if input.KeyCode==Enum.KeyCode.Escape then
		finishDrag(false);refresh(false)
		finishParameterDrag(false)
		if placing then stopPlacement() end
	end
end)
plugin.Deactivation:Connect(function() placing=false; placeButton:SetActive(false); if marker then marker:Destroy(); marker=nil end end)
plugin.Unloading:Connect(function() unloaded=true;finishParameterDrag(false);finishDrag(false);if marker then marker:Destroy() end;widget:Destroy() end)
print('[BoraTree] v0.4.3 ready: smooth wood / dock sliders')
task.spawn(function()
	local image=Instance.new('ImageLabel'); image.Image=catalog.Leaf.Texture
	local mesh=Instance.new('SpecialMesh'); mesh.MeshType=Enum.MeshType.FileMesh; mesh.MeshId=catalog.Wood.Mesh; mesh.TextureId=catalog.ProceduralBark
	local failures={}
	local ok,err=pcall(function() ContentProvider:PreloadAsync({image,mesh},function(uri,state) if state~=Enum.AssetFetchStatus.Success then table.insert(failures,uri) end end) end)
	image:Destroy(); mesh:Destroy()
	assetsReady=ok and #failures==0
	if assetsReady then print('[BoraTree] procedural assets ready') else warn('[BoraTree] missing local assets: '..tostring(err or table.concat(failures,', '))) end
end)
task.defer(function()
	local folder=workspace:FindFirstChild('BoraTrees'); if not folder then return end
	if game:GetService('ServerScriptService'):FindFirstChild('BoraProceduralRuntime') then ensureRuntime() end
	busy=true
	for _,tree in folder:GetChildren() do
		if factory.isTree(tree) and tree:GetAttribute('SchemaVersion')==4 and tree:GetAttribute('LiveMesh') then
			local ok,err=pcall(function() factory.rebuild(tree,Parameters.fromModel(tree),progress) end)
			if ok then print('[BoraTree] restored recipe: '..(tree:GetAttribute('ObjectId') or tree.Name)) else warn('[BoraTree] restore: '..tostring(err)) end
		end
	end
	busy=false
end)
