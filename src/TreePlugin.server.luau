-- 유일한 설치 버튼과 선택한 나무의 성장 인스펙터를 연결하는 Studio 전용 코드입니다.
if not plugin then return end
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local History = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")
local rules = require(script.Parent.GrowthMath)
local catalog = require(script.Parent.TreeAssetCatalog)
local factory = require(script.Parent.GrowthTreeFactory)({
	Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum, UDim2 = UDim2,
}, rules, catalog)

local toolbar = plugin:CreateToolbar("보라동 나무")
local install = toolbar:CreateButton("BoraTreePlace_v2", "지면을 클릭해 가장 작은 은행나무를 설치합니다", "", "나무 설치")
install.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGuiAsync("BoraTreeInspector_v2",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 310, 260, 270, 220))
widget.Title = "나무 인스펙터"
local background = Instance.new("Frame")
background.Size, background.BackgroundColor3, background.BorderSizePixel = UDim2.fromScale(1, 1), Color3.fromRGB(30, 34, 40), 0
background.Parent = widget
local function text(name, value, position, size, fontSize, color)
	local label = Instance.new("TextLabel")
	label.Name, label.Text, label.Position, label.Size = name, value, position, size
	label.BackgroundTransparency, label.Font, label.TextSize = 1, Enum.Font.SourceSans, fontSize
	label.TextColor3, label.TextXAlignment, label.TextWrapped = color or Color3.fromRGB(231, 236, 239), Enum.TextXAlignment.Left, true
	label.Parent = background
	return label
end
text("Species", "은행나무", UDim2.fromOffset(20, 15), UDim2.new(1, -40, 0, 30), 24)
text("Description", "선택한 나무의 성장 정도를 조절하세요.", UDim2.fromOffset(20, 51), UDim2.new(1, -40, 0, 25), 15, Color3.fromRGB(158, 173, 184))
text("GrowthTitle", "성장 정도", UDim2.fromOffset(20, 94), UDim2.new(.5, -20, 0, 24), 17)
local percentage = text("Percentage", "0%", UDim2.new(.5, 0, 0, 94), UDim2.new(.5, -20, 0, 24), 19, Color3.fromRGB(220, 190, 119))
percentage.TextXAlignment = Enum.TextXAlignment.Right
local track = Instance.new("TextButton")
track.Name, track.Text, track.Position, track.Size = "GrowthSlider", "", UDim2.fromOffset(20, 128), UDim2.new(1, -40, 0, 30)
track.BackgroundTransparency, track.AutoButtonColor, track.Parent = 1, false, background
local rail = Instance.new("Frame")
rail.Position, rail.Size, rail.BackgroundColor3, rail.BorderSizePixel = UDim2.fromOffset(0, 12), UDim2.new(1, 0, 0, 6), Color3.fromRGB(69, 78, 86), 0
rail.Parent = track
local railCorner = Instance.new("UICorner")
railCorner.CornerRadius, railCorner.Parent = UDim.new(1, 0), rail
local fill = Instance.new("Frame")
fill.Size, fill.BackgroundColor3, fill.BorderSizePixel, fill.Parent = UDim2.fromScale(0, 1), Color3.fromRGB(220, 190, 119), 0, rail
local fillCorner = railCorner:Clone()
fillCorner.Parent = fill
local knob = Instance.new("TextButton")
knob.Text, knob.Size, knob.AnchorPoint = "", UDim2.fromOffset(20, 20), Vector2.new(.5, .5)
knob.Position, knob.BackgroundColor3, knob.BorderSizePixel = UDim2.fromScale(0, .5), Color3.fromRGB(241, 222, 174), 0
knob.AutoButtonColor, knob.Parent = false, track
local knobCorner = Instance.new("UICorner")
knobCorner.CornerRadius, knobCorner.Parent = UDim.new(1, 0), knob
text("Small", "어린 나무", UDim2.fromOffset(20, 164), UDim2.new(.5, -20, 0, 22), 14, Color3.fromRGB(158, 173, 184))
local adult = text("Adult", "다 자란 나무", UDim2.new(.5, 0, 0, 164), UDim2.new(.5, -20, 0, 22), 14, Color3.fromRGB(158, 173, 184))
adult.TextXAlignment = Enum.TextXAlignment.Right
local status = text("Status", "드래그 한 번은 Ctrl+Z 한 번으로 되돌릴 수 있어요.", UDim2.fromOffset(20, 203), UDim2.new(1, -40, 0, 36), 14, Color3.fromRGB(158, 173, 184))

local mouse = plugin:GetMouse()
local assetsReady = false
local placing, marker, hit, current, dragRecord, dragInput
local growthConnection, ancestryConnection
local function refresh()
	if not current or not current.Parent then return end
	local value = current:GetAttribute("Growth") or 0
	percentage.Text = string.format("%d%%", math.floor(value * 100 + .5))
	fill.Size, knob.Position = UDim2.fromScale(value, 1), UDim2.fromScale(value, .5)
end
local function endDrag(commit)
	local id = dragRecord
	dragRecord, dragInput = nil, nil
	if id then
		local ok, errorMessage = pcall(function()
			History:FinishRecording(id, if commit then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
		end)
		if not ok then warn("[BoraTree] undo recording: " .. tostring(errorMessage)) end
	end
	refresh()
end
local function inspect(model)
	if current == model then if model then widget.Enabled = true; refresh() end; return end
	endDrag(true)
	if growthConnection then growthConnection:Disconnect(); growthConnection = nil end
	if ancestryConnection then ancestryConnection:Disconnect(); ancestryConnection = nil end
	current = model
	widget.Enabled = model ~= nil
	if model then
		growthConnection = model:GetAttributeChangedSignal("Growth"):Connect(refresh)
		ancestryConnection = model.AncestryChanged:Connect(function()
			if not model.Parent then inspect(nil) end
		end)
		status.Text = if model:GetAttribute("SchemaVersion") == 3 then "드래그 한 번은 Ctrl+Z 한 번으로 되돌릴 수 있어요." else "이전 버전 나무입니다. 새 나무를 설치하면 개선된 모델을 사용할 수 있어요."
		refresh()
	end
end
local function selectedTree()
	local selected = Selection:Get()
	if #selected ~= 1 then return nil end
	local item = selected[1]
	while item and item ~= workspace do
		if factory.isTree(item) then return item end
		item = item.Parent
	end
	return nil
end
local function updateDrag()
	if not dragRecord or not current then return end
	local size = track.AbsoluteSize.X
	if size <= 0 then return end
	local point = widget:GetRelativeMousePosition()
	local value = math.clamp((point.X - track.AbsolutePosition.X) / size, 0, 1)
	if math.abs(value - (current:GetAttribute("Growth") or 0)) < .0005 then return end
	local ok, errorMessage = pcall(function() factory.setGrowth(current, value) end)
	if not ok then
		endDrag(false)
		status.Text = "변경하지 못했습니다. 나무 구조를 확인하세요."
		warn("[BoraTree] growth: " .. tostring(errorMessage))
	end
end
local function beginDrag(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not current or RunService:IsRunning() then return end
	endDrag(true)
	local ok, errorMessage = pcall(function() factory.validate(current) end)
	if not ok then
		status.Text = if current:GetAttribute("SchemaVersion") ~= 3 then "이전 버전 나무입니다. 새 나무를 설치해 주세요." else "나무 구조를 확인하세요."
		warn(errorMessage)
		return
	end
	dragRecord = History:TryBeginRecording("BoraTreeGrowth", "나무 성장 조절")
	if not dragRecord then status.Text = "다른 편집이 끝난 뒤 다시 시도하세요."; return end
	dragInput = input
	updateDrag()
end
track.InputBegan:Connect(beginDrag)
knob.InputBegan:Connect(beginDrag)
local function inputEnded(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then endDrag(true) end
end
track.InputEnded:Connect(inputEnded)
knob.InputEnded:Connect(inputEnded)
UserInputService.InputEnded:Connect(inputEnded)
widget.WindowFocusReleased:Connect(function() endDrag(true) end)
widget:BindToClose(function() endDrag(true); widget.Enabled = false end)
RunService.Heartbeat:Connect(function()
	if dragRecord then
		if not current or not current.Parent or RunService:IsRunning() then endDrag(false)
		elseif dragInput and dragInput.UserInputState == Enum.UserInputState.End then endDrag(true)
		else updateDrag() end
	end
end)

local function stopPlacement()
	placing, hit = false, nil
	install:SetActive(false)
	if marker then marker:Destroy(); marker = nil end
	plugin:Deactivate()
end
local function treeFolder()
	local folder = workspace:FindFirstChild("BoraTrees")
	if folder then assert(folder:IsA("Folder"), "BoraTrees must be a Folder"); return folder end
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "BoraTrees", workspace
	return folder
end
local function pickGround()
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	local excluded = {}
	if marker then table.insert(excluded, marker) end
	local trees = workspace:FindFirstChild("BoraTrees")
	if trees then table.insert(excluded, trees) end
	parameters.FilterDescendantsInstances = excluded
	local ray = mouse.UnitRay
	local result = workspace:Raycast(ray.Origin, ray.Direction * 3000, parameters)
	if result and result.Normal.Y >= .65 then return result end
	return nil
end
local function moveMarker()
	if not placing or not marker then return end
	hit = pickGround()
	if not hit then marker.Transparency = 1; return end
	local up = hit.Normal
	local right = up:Cross(Vector3.zAxis).Unit
	local frame = CFrame.fromMatrix(hit.Position + up * .055, right, up, right:Cross(up))
	marker.CFrame, marker.Transparency = frame * CFrame.Angles(0, 0, math.pi / 2), .35
end
install.Click:Connect(function()
	endDrag(true)
	if placing then stopPlacement(); return end
	if RunService:IsRunning() then warn("[보라동 나무] Play를 중지한 뒤 설치하세요."); return end
	if not assetsReady then warn("[보라동 나무] 나무 에셋을 로딩 중이거나 로컬 파일이 누락됐습니다. 출력 창을 확인하세요."); return end
	marker = Instance.new("Part")
	marker.Name, marker.Shape, marker.Size = "BoraTreePlacementMarker", Enum.PartType.Cylinder, Vector3.new(.05, 2, 2)
	marker.Anchored, marker.CanCollide, marker.CanTouch, marker.CanQuery = true, false, false, false
	marker.CastShadow, marker.Material, marker.Color = false, Enum.Material.Neon, Color3.fromRGB(79, 206, 184)
	marker.Transparency, marker.Parent = 1, workspace
	placing = true
	plugin:Activate(true)
	install:SetActive(true)
	moveMarker()
end)
mouse.Move:Connect(moveMarker)
mouse.Button1Down:Connect(function()
	if not placing or RunService:IsRunning() then return end
	local result = pickGround()
	if not result then return end
	local id = History:TryBeginRecording("BoraTreePlace", "나무 설치")
	if not id then return end
	local ok, model = pcall(function()
		local tree = factory.create({ Growth = 0, Seed = 42, ObjectId = HttpService:GenerateGUID(false) }, CFrame.new(result.Position))
		tree.Parent = treeFolder()
		return tree
	end)
	History:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	if ok then
		stopPlacement()
		Selection:Set({ model })
		inspect(model)
	else warn("[BoraTree] placement: " .. tostring(model)) end
end)
Selection.SelectionChanged:Connect(function() inspect(selectedTree()) end)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Escape and placing then stopPlacement() end
end)
plugin.Deactivation:Connect(function()
	placing, hit = false, nil
	install:SetActive(false)
	if marker then marker:Destroy(); marker = nil end
end)
plugin.Unloading:Connect(function()
	endDrag(true)
	stopPlacement()
	if growthConnection then growthConnection:Disconnect() end
	if ancestryConnection then ancestryConnection:Disconnect() end
	widget:Destroy()
end)
print("[BoraTree] v0.3 ready: connected wood + layered leaf clusters")
task.spawn(function()
	local content, failed, assetCount = {}, {}, 0
	for _, asset in { catalog.Wood } do
		-- URL 문자열만 전달하면 Studio가 메시를 이미지로 해석합니다. 형식을 가진 Instance를 전달합니다.
		local preloadMesh = Instance.new("SpecialMesh")
		preloadMesh.MeshType = Enum.MeshType.FileMesh
		preloadMesh.MeshId, preloadMesh.TextureId = asset.Mesh, asset.Texture or ""
		table.insert(content, preloadMesh)
		assetCount += if asset.Texture then 2 else 1
	end
	local foliage = Instance.new("ImageLabel")
	foliage.Image = catalog.Leaf.Texture
	table.insert(content, foliage)
	assetCount += 1
	local ok, errorMessage = pcall(function()
		ContentProvider:PreloadAsync(content, function(uri, fetchStatus)
			if fetchStatus ~= Enum.AssetFetchStatus.Success then table.insert(failed, uri) end
		end)
	end)
	for _, preloadMesh in content do preloadMesh:Destroy() end
	assetsReady = ok and #failed == 0
	if assetsReady then print("[BoraTree] assets ready: " .. assetCount)
	else warn("[BoraTree] assets unavailable: " .. tostring(errorMessage or table.concat(failed, ", "))) end
end)
