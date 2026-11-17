-- 끝점은 도로 표면 중앙입니다. 위치와 높이 차이를 함께 써서 평지·경사를 만듭니다.
return function(api)
	local Instance, Vector3, CFrame, Color3, Enum = api.Instance, api.Vector3, api.CFrame, api.Color3, api.Enum
	local Factory = {}
	local function numeric(value, default, minimum, maximum, label)
		if value == nil then value = default end
		assert(type(value) == "number" and value == value and value >= minimum and value <= maximum,
			label .. " must be between " .. minimum .. " and " .. maximum)
		return value
	end
	local function nodeId(point)
		return string.format("%.2f,%.2f,%.2f", point.X, point.Y, point.Z)
	end
	local function slab(parent, name, size, frame, color, material, collidable)
		local part = Instance.new("Part")
		part.Name, part.Size, part.CFrame, part.Color = name, size, frame, color
		part.Material, part.Anchored = material, true
		part.CanCollide, part.CanTouch, part.CanQuery = collidable, false, collidable
		part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		part.Parent = parent
		return part
	end

	function Factory.create(config)
		local startPoint, endPoint = config.Start, config.End
		assert(typeof(startPoint) == "Vector3" and typeof(endPoint) == "Vector3", "Start and End must be Vector3")
		local delta = endPoint - startPoint
		local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
		assert(horizontal == horizontal and horizontal >= 2 and horizontal <= 512, "Road horizontal length must be 2–512 studs")
		local grade = math.abs(delta.Y) / horizontal
		assert(grade <= 0.25, "Road grade must be at most 25%; move the end point farther away")
		local width = numeric(config.Width, 14, 4, 40, "Width")
		local sidewalk = numeric(config.SidewalkWidth, 3, 0, 8, "SidewalkWidth")
		local thickness, curbHeight = 0.6, 0.35
		local frame = CFrame.lookAt((startPoint + endPoint) / 2, endPoint)
		local length = delta.Magnitude
		local model = Instance.new("Model")
		model.Name = if grade > 0.001 then "SlopeRoad" else "StraightRoad"
		model:SetAttribute("AssetKind", "Road")
		model:SetAttribute("AssetId", "Bora.Road.Straight")
		model:SetAttribute("SchemaVersion", 1)
		model:SetAttribute("ObjectId", config.ObjectId)
		model:SetAttribute("StartPosition", startPoint)
		model:SetAttribute("EndPosition", endPoint)
		model:SetAttribute("StartNodeId", nodeId(startPoint))
		model:SetAttribute("EndNodeId", nodeId(endPoint))
		model:SetAttribute("Width", width)
		model:SetAttribute("SidewalkWidth", sidewalk)
		model:SetAttribute("GradePercent", grade * 100)
		model.WorldPivot = frame
		slab(model, "Asphalt", Vector3.new(width, thickness, length), frame * CFrame.new(0, -thickness / 2, 0),
			Color3.fromRGB(58, 61, 66), Enum.Material.Asphalt, true)
		if sidewalk > 0 then
			for _, side in { -1, 1 } do
				slab(model, if side == -1 then "SidewalkLeft" else "SidewalkRight",
					Vector3.new(sidewalk, thickness + curbHeight, length),
					frame * CFrame.new(side * (width + sidewalk) / 2, (curbHeight - thickness) / 2, 0),
					Color3.fromRGB(174, 174, 167), Enum.Material.Concrete, true)
			end
		end
		for _, offset in { -0.16, 0.16 } do
			slab(model, "CenterLine", Vector3.new(0.1, 0.025, length), frame * CFrame.new(offset, 0.018, 0),
				Color3.fromRGB(231, 186, 64), Enum.Material.SmoothPlastic, false)
		end
		return model
	end

	return Factory
end
