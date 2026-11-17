-- Studio 편집 도구입니다. 플레이 중 실행하는 게임 스크립트가 아닙니다.
if not plugin then return end

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local History = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local definitions = require(script.Parent.Definitions)
local api = { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
local trees = require(script.Parent.TreeFactory)(api, definitions)
local roads = require(script.Parent.RoadFactory)(api)

local toolbar = plugin:CreateToolbar("보라동 제작")
local openButton = toolbar:CreateButton("BoraWorldKit", "나무와 직선·경사 도로 배치", "", "에셋 배치")
local widget = plugin:CreateDockWidgetPluginGui("BoraWorldKit_v1", DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right, false, false, 350, 660, 300, 380))
widget.Title = "보라동 에셋 도구 · v0.1"
local scroll = Instance.new("ScrollingFrame")
scroll.Size, scroll.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.fromRGB(35, 38, 44)
scroll.BorderSizePixel, scroll.ScrollBarThickness = 0, 6
scroll.AutomaticCanvasSize, scroll.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
scroll.Parent = widget
local padding = Instance.new("UIPadding")
padding.PaddingTop, padding.PaddingBottom = UDim.new(0, 12), UDim.new(0, 12)
padding.PaddingLeft, padding.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
padding.Parent = scroll
local layout = Instance.new("UIListLayout")
layout.Padding, layout.SortOrder, layout.Parent = UDim.new(0, 6), Enum.SortOrder.LayoutOrder, scroll
local order = 0
local function base(class, height)
	local gui = Instance.new(class)
	order += 1
	gui.LayoutOrder, gui.Size = order, UDim2.new(1, -8, 0, height)
	gui.BackgroundColor3, gui.BorderSizePixel = Color3.fromRGB(54, 59, 68), 0
	gui.Font, gui.TextSize, gui.TextColor3 = Enum.Font.SourceSans, 16, Color3.fromRGB(235, 239, 245)
	gui.Parent = scroll
	return gui
end
local function label(text, height)
	local gui = base("TextLabel", height or 24)
	gui.Text, gui.BackgroundTransparency = text, 1
	gui.TextXAlignment, gui.TextWrapped = Enum.TextXAlignment.Left, true
	return gui
end
local function field(title, value)
	label(title)
	local gui = base("TextBox", 30)
	gui.Text, gui.ClearTextOnFocus = tostring(value), false
	return gui
end
local function button(text, callback)
	local gui = base("TextButton", 32)
	gui.Text = text
	gui.MouseButton1Click:Connect(callback)
	return gui
end

label("나무 · 수종과 크기 설정")
local speciesIndex, seasonIndex, branchIndex = 1, 2, 2
local seasonMode = "World"
local speciesKeys, branchKeys = { "Ginkgo", "Maple", "Pine" }, { "Sparse", "Normal", "Dense" }
local speciesButton, seasonButton, branchButton
speciesButton = button("수종: 은행나무", function()
	speciesIndex = speciesIndex % #speciesKeys + 1
	speciesButton.Text = "수종: " .. definitions.Species[speciesKeys[speciesIndex]].Label
end)
local height = field("높이 (4–40 studs)", 14)
local diameter = field("줄기 지름 (0.2–3)", 0.7)
local canopy = field("수관 너비 (2–24)", 9)
local seed = field("변형 시드 (정수)", 42)
local branchLabels = { "적음", "보통", "많음" }
branchButton = button("가지: 보통", function()
	branchIndex = branchIndex % #branchKeys + 1
	branchButton.Text = "가지: " .. branchLabels[branchIndex]
end)
local seasonLabels = { "봄", "여름", "가을", "겨울" }
seasonButton = button("계절: 여름", function()
	seasonIndex = seasonIndex % #definitions.Seasons + 1
	seasonButton.Text = "계절: " .. seasonLabels[seasonIndex]
end)
local seasonModeButton
seasonModeButton = button("나무 계절: 월드 따라감", function()
	seasonMode = if seasonMode == "World" then "Fixed" else "World"
	seasonModeButton.Text = if seasonMode == "World" then "나무 계절: 월드 따라감" else "나무 계절: 선택한 계절 고정"
end)
local status = label("설정 후 배치 버튼을 누르세요.", 54)
local mouse = plugin:GetMouse()
local mode, startPoint, preview, activeTreeConfig, activeRoadConfig

local function cancel()
	mode, startPoint, activeTreeConfig, activeRoadConfig = nil, nil, nil, nil
	if preview then preview:Destroy(); preview = nil end
	mouse.TargetFilter = nil
	plugin:Deactivate()
end
local function treeConfig()
	-- 숫자가 아닌 입력을 조용히 기본값으로 바꾸지 않고 사용자에게 알려줍니다.
	local function read(box, name)
		local value = tonumber(box.Text)
		assert(value, name .. "에 숫자를 입력하세요.")
		return value
	end
	return trees.validate({
		Species = speciesKeys[speciesIndex], Height = read(height, "높이"),
		TrunkDiameter = read(diameter, "줄기 지름"), CanopyWidth = read(canopy, "수관 너비"),
		Seed = read(seed, "시드"), BranchPreset = branchKeys[branchIndex],
		Season = if seasonMode == "World" then (workspace:GetAttribute("WorldSeason") or definitions.Seasons[seasonIndex])
			else definitions.Seasons[seasonIndex], SeasonMode = seasonMode,
	})
end
local function record(title, action)
	if RunService:IsRunning() then status.Text = "Play를 중지한 뒤 편집하세요."; return end
	local id = History:TryBeginRecording("BoraWorldKit_" .. title, title)
	if not id then status.Text = "다른 편집 기록이 끝난 뒤 다시 시도하세요."; return end
	local ok, result = pcall(action)
	History:FinishRecording(id, if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel)
	status.Text = if ok then title .. " 완료 · Ctrl+Z로 되돌릴 수 있어요." else tostring(result)
	return ok, result
end
local function folder()
	local root = workspace:FindFirstChild("BoraPlacedAssets")
	if root then assert(root:IsA("Folder"), "BoraPlacedAssets 이름은 Folder에만 사용하세요."); return root end
	root = Instance.new("Folder")
	root.Name, root.Parent = "BoraPlacedAssets", workspace
	return root
end
local function previewTree()
	preview = trees.create(activeTreeConfig)
	preview.Name = "BoraPlacementPreview"
	preview:SetAttribute("AssetKind", "Preview")
	for _, item in preview:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide, item.CanTouch, item.CanQuery, item.CastShadow = false, false, false, false
			if item.Transparency < 1 then item.Transparency = 0.6 end
		end
	end
	mouse.TargetFilter = preview
end

button("나무 배치 · 지면 클릭", function()
	cancel()
	if RunService:IsRunning() then status.Text = "Play를 중지한 뒤 편집하세요."; return end
	local ok, config = pcall(treeConfig)
	if not ok then status.Text = tostring(config); return end
	mode, activeTreeConfig = "Tree", config
	previewTree()
	plugin:Activate(true)
	status.Text = "지면을 클릭하면 배치합니다. 취소 버튼으로 종료하세요."
end)
button("선택한 나무를 현재 설정으로 재생성", function()
	cancel()
	local selected = Selection:Get()
	if #selected ~= 1 or not selected[1]:IsA("Model") or selected[1]:GetAttribute("AssetKind") ~= "Tree" then
		status.Text = "Explorer에서 나무 Model 하나를 선택하세요."; return
	end
	local ok, config = pcall(treeConfig)
	if not ok then status.Text = tostring(config); return end
	config.ObjectId = selected[1]:GetAttribute("ObjectId")
	record("나무 재생성", function()
		local replacement = trees.rebuild(selected[1], config)
		Selection:Set({ replacement })
	end)
end)
button("월드 나무에 선택한 계절 적용", function()
	cancel()
	record("계절 변경", function()
		local season = definitions.Seasons[seasonIndex]
		workspace:SetAttribute("WorldSeason", season)
		for _, item in workspace:GetDescendants() do
			if item:IsA("Model") and item:GetAttribute("AssetKind") == "Tree"
				and item:GetAttribute("SeasonMode") == "World" then trees.applySeason(item, season) end
		end
	end)
end)

label("도로 · 표면 시작점과 끝점 연결", 30)
local roadWidth = field("차도 폭 (4–40)", 14)
local sidewalkWidth = field("양쪽 보도 폭 (각 0–8)", 3)
local roadRise = field("끝점 추가 높이 (studs, 경사 최대 25%)", 0)
button("도로 배치 · 시작점 → 끝점 클릭", function()
	cancel()
	if RunService:IsRunning() then status.Text = "Play를 중지한 뒤 편집하세요."; return end
	local width, sidewalk, rise = tonumber(roadWidth.Text), tonumber(sidewalkWidth.Text), tonumber(roadRise.Text)
	if not width or not sidewalk or not rise or width < 4 or width > 40 or sidewalk < 0 or sidewalk > 8
		or rise ~= rise or math.abs(rise) > 128 then
		status.Text = "폭과 높이에 허용 범위의 숫자를 입력하세요."; return
	end
	activeRoadConfig, mode = { Width = width, SidewalkWidth = sidewalk, Rise = rise }, "Road"
	plugin:Activate(true)
	status.Text = "도로 표면의 시작점을 클릭하세요. 끝점 높이는 클릭한 높이 + 추가 높이입니다."
end)
button("배치 취소", function() cancel(); status.Text = "배치를 종료했습니다." end)
label("원형 에셋 v0.1 · 직선/경사만 지원\n지형 자동 수정과 곡선·교차로 연결은 다음 단계입니다.", 60)

mouse.Move:Connect(function()
	if mode == "Tree" and preview then
		if mouse.Target then preview.Parent = workspace; preview:PivotTo(CFrame.new(mouse.Hit.Position))
		else preview.Parent = nil end
	end
end)
mouse.Button1Down:Connect(function()
	if not mode or not mouse.Target then return end
	local position = mouse.Hit.Position
	if mode == "Tree" then
		record("나무 배치", function()
			local config = table.clone(activeTreeConfig)
			config.ObjectId = HttpService:GenerateGUID(false)
			if config.SeasonMode == "World" then config.Season = workspace:GetAttribute("WorldSeason") or config.Season end
			local model = trees.create(config, CFrame.new(position))
			model.Parent = folder()
		end)
	elseif not startPoint then
		-- 평평한 지면과 도로 표면이 겹쳐 깜빡이지 않도록 약간 띄웁니다.
		startPoint = position + Vector3.new(0, 0.05, 0)
		status.Text = "시작점 저장 완료. 도로 끝점을 클릭하세요."
	else
		local ok = record("도로 배치", function()
			local model = roads.create({ Start = startPoint,
				End = position + Vector3.new(0, activeRoadConfig.Rise + 0.05, 0),
				Width = activeRoadConfig.Width, SidewalkWidth = activeRoadConfig.SidewalkWidth,
				ObjectId = HttpService:GenerateGUID(false) })
			model.Parent = folder()
			Selection:Set({ model })
		end)
		if ok then startPoint = nil end
	end
end)
openButton.Click:Connect(function() widget.Enabled = not widget.Enabled end)
widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	openButton:SetActive(widget.Enabled)
	if not widget.Enabled then cancel() end
end)
plugin.Deactivation:Connect(function()
	mode, startPoint = nil, nil
	if preview then preview:Destroy(); preview = nil end
	mouse.TargetFilter = nil
end)
plugin.Unloading:Connect(cancel)
