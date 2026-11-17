-- 엔진 객체 생성 부분을 함수로 묶어 Studio와 파일 빌드에서 같은 코드를 실행합니다.
return function(api, definitions)
	local Instance, Vector3, CFrame, Color3, Enum = api.Instance, api.Vector3, api.CFrame, api.Color3, api.Enum
	local Factory = {}
	local function number(value, default, minimum, maximum, label)
		if value == nil then value = default end
		assert(type(value) == "number" and value == value and value >= minimum and value <= maximum,
			label .. " must be between " .. minimum .. " and " .. maximum)
		return value
	end

	local function color(rgb)
		return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	end

	local function part(parent, name, size, frame, tint, shape, collidable)
		local item = Instance.new("Part")
		item.Name, item.Size, item.CFrame = name, size, frame
		item.Shape = shape or Enum.PartType.Block
		item.Material = Enum.Material.SmoothPlastic
		item.Color, item.Anchored = tint, true
		item.CanCollide, item.CanTouch, item.CanQuery = collidable, false, collidable
		item.TopSurface, item.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		item.Parent = parent
		return item
	end

	local function beam(parent, name, a, b, diameter, tint, collidable)
		local delta = b - a
		-- 수직 줄기는 기본 위쪽 벡터와 평행하므로 보조 축을 바꿔 회전을 안정화합니다.
		local up = if math.abs(delta.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
		-- Cylinder의 길이축은 X이므로 X축을 가지 방향에 맞춥니다.
		return part(parent, name, Vector3.new(delta.Magnitude, diameter, diameter),
			CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, math.pi / 2, 0),
			tint, Enum.PartType.Cylinder, collidable)
	end

	function Factory.validate(config)
		local species = config.Species or "Ginkgo"
		assert(definitions.Species[species], "Unknown tree species: " .. tostring(species))
		local branchPreset = config.BranchPreset or "Normal"
		assert(definitions.BranchCounts[branchPreset], "Unknown branch preset")
		local season = config.Season or "Summer"
		assert(table.find(definitions.Seasons, season), "Unknown season")
		local seasonMode = config.SeasonMode or "World"
		assert(seasonMode == "World" or seasonMode == "Fixed", "SeasonMode must be World or Fixed")
		local seed = number(config.Seed, 42, 0, 2147483646, "Seed")
		assert(seed % 1 == 0, "Seed must be an integer")
		return {
			Species = species, Height = number(config.Height, 14, 4, 40, "Height"),
			TrunkDiameter = number(config.TrunkDiameter, 0.7, 0.2, 3, "TrunkDiameter"),
			CanopyWidth = number(config.CanopyWidth, 9, 2, 24, "CanopyWidth"),
			BranchPreset = branchPreset, Seed = seed, Season = season, SeasonMode = seasonMode,
			ObjectId = config.ObjectId,
		}
	end

	function Factory.applySeason(model, season)
		assert(table.find(definitions.Seasons, season), "Unknown season")
		local species = model:GetAttribute("Species")
		local style = definitions.Species[species]
		assert(style, "Model is not a supported tree")
		local leaves = model:FindFirstChild("Foliage")
		assert(leaves, "Tree has no Foliage folder")
		for _, leaf in leaves:GetChildren() do
			if leaf:IsA("BasePart") then
				leaf.Color = color(style[season])
				leaf.Transparency = if season == "Winter" and species ~= "Pine" then 1 else 0
				leaf.CastShadow = leaf.Transparency == 0
			end
		end
		model:SetAttribute("Season", season)
	end

	function Factory.create(config, transform)
		local settings = Factory.validate(config)
		local style = definitions.Species[settings.Species]
		local model = Instance.new("Model")
		model.Name = settings.Species .. "Tree"
		model:SetAttribute("AssetKind", "Tree")
		model:SetAttribute("AssetId", "Bora.Tree." .. settings.Species)
		model:SetAttribute("SchemaVersion", definitions.SchemaVersion)
		for key, value in settings do model:SetAttribute(key, value) end
		local frame = transform or CFrame.new()
		local h, d, w = settings.Height, settings.TrunkDiameter, settings.CanopyWidth
		local foliage = Instance.new("Folder")
		foliage.Name, foliage.Parent = "Foliage", model
		beam(model, "Trunk", frame.Position, (frame * CFrame.new(0, h * 0.76, 0)).Position,
			d, color(style.Bark), true)
		-- 편집·재생성을 위한 기준점은 줄기 중심이 아니라 지면 접점입니다.
		model.WorldPivot = frame
		local randomState = settings.Seed + 1
		local function random()
			randomState = (randomState * 48271) % 2147483647
			return randomState / 2147483647
		end
		local branchCount = definitions.BranchCounts[settings.BranchPreset]
		for index = 1, branchCount do
			local angle = index * math.pi * 2 / branchCount + random() * 0.3
			local radius = w * (0.23 + random() * 0.08)
			local branchStart = (frame * CFrame.new(0, h * (0.38 + index / branchCount * 0.15), 0)).Position
			local tip = Vector3.new(math.cos(angle) * radius, h * (0.67 + random() * 0.12), math.sin(angle) * radius)
			beam(model, "Branch" .. index, branchStart, (frame * CFrame.new(tip)).Position,
				math.max(0.12, d * 0.36), color(style.Bark), false)
			if settings.Species ~= "Pine" then
				local shapeSize = if settings.Species == "Ginkgo"
					then Vector3.new(w * 0.52, h * 0.28, w * 0.44)
					else Vector3.new(w * 0.57, h * 0.32, w * 0.57)
				part(foliage, "Crown" .. index, shapeSize, frame * CFrame.new(tip),
					color(style[settings.Season]), Enum.PartType.Ball, false)
			end
		end
		if settings.Species == "Pine" then
			-- 외부 메시 없이 구분 가능한 층형 수관을 만드는 초기 원형입니다.
			for tier = 1, 4 do
				local width = w * (1 - (tier - 1) * 0.19)
				part(foliage, "NeedleTier" .. tier, Vector3.new(width, h * 0.23, width),
					frame * CFrame.new(0, h * (0.48 + (tier - 1) * 0.125), 0),
					color(style[settings.Season]), Enum.PartType.Ball, false)
			end
		else
			part(foliage, "CrownTop", Vector3.new(w * 0.68, h * 0.30, w * 0.68),
				frame * CFrame.new(0, h * 0.85, 0), color(style[settings.Season]), Enum.PartType.Ball, false)
		end
		Factory.applySeason(model, settings.Season)
		return model
	end

	-- 기존 모델을 건드리기 전에 새 모델을 완성해서 수동 편집 유실을 줄입니다.
	function Factory.rebuild(model, overrides)
		assert(model:GetAttribute("AssetKind") == "Tree", "Select a generated tree")
		local config = model:GetAttributes()
		for key, value in overrides or {} do config[key] = value end
		local replacement = Factory.create(config, model:GetPivot())
		replacement.Name, replacement.Parent = model.Name, model.Parent
		model:Destroy()
		return replacement
	end

	return Factory
end
