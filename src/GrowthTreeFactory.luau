-- 하나로 이어진 목재 + 여러 각도로 고정된 잎 뭉치 카드. 카메라 추적 없음.
return function(api, rules, catalog)
	local Instance, Vector3, CFrame, Color3, Enum = api.Instance, api.Vector3, api.CFrame, api.Color3, api.Enum
	local UDim2 = api.UDim2
	local Factory = {}
	local cardCount = #catalog.CrownAnchors * 3
	local function part(parent, name)
		local p = Instance.new("Part")
		p.Name, p.Anchored = name, true
		p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Material, p.Color, p.Parent = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), parent
		return p
	end
	local function leafCard(parent, name)
		local p = part(parent, name)
		p.Transparency, p.CastShadow = 1, false
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local surface = Instance.new("SurfaceGui")
			surface.Name, surface.Face = face.Name, face
			surface.AlwaysOnTop, surface.LightInfluence, surface.Active = false, 1, false
			surface.SizingMode, surface.PixelsPerStud, surface.MaxDistance = Enum.SurfaceGuiSizingMode.PixelsPerStud, 96, 300
			surface.Parent = p
			local image = Instance.new("ImageLabel")
			image.Name, image.Image = "Foliage", catalog.Leaf.Texture
			image.BackgroundTransparency, image.Size, image.Parent = 1, UDim2.fromScale(1, 1), surface
		end
		return p
	end
	function Factory.layout(value, seed)
		local d = rules.dimensions(value)
		assert(type(seed) == "number" and seed % 1 == 0 and seed >= 0 and seed <= 2147483646, "Invalid seed")
		local state = seed + 1
		local function random()
			state = state * 48271 % 2147483647
			return state / 2147483647
		end
		-- One transform keeps every welded branch collar connected.
		local width = catalog.WoodHeight * d.Diameter / 2.2
		local scale = Vector3.new(width, d.Height, width)
		local out = { Dimensions = d, Leaves = {}, Trunk = {
			Frame = CFrame.new(0, d.Height / 2, 0), Size = catalog.Wood.Bounds * scale, Scale = scale,
		} }
		for _, anchor in catalog.CrownAnchors do
			local center = anchor * scale
			local yaw = random() * math.pi * 2
			local size = d.LeafSize * (.88 + random() * .26)
			for k = 1, 3 do
				local offset = Vector3.new((random()-.5)*size*.75, (random()-.5)*size*.48, (random()-.5)*size*.75)
				-- Disperse the planes in depth. Inner caps bridge gaps between outer sprigs.
				local cardCenter = if k == 3 then center * Vector3.new(.78,1,.78) else center
				local tilt = if k == 3 then math.rad(48 + random()*25) else math.rad(-42 + random()*84)
				local roll = math.rad(-17+random()*34)
				table.insert(out.Leaves, { Frame = CFrame.new(cardCenter+offset) * CFrame.Angles(0,yaw+(k-1)*math.pi/2,0) * CFrame.Angles(tilt,0,roll),
					Size = Vector3.new(size, size*(.83+random()*.13), .02), Scale = Vector3.one,
					Tint = .91 + random()*.09 })
			end
		end
		return out
	end
	function Factory.isTree(model)
		return model and model:IsA("Model") and model:GetAttribute("AssetKind") == "BoraGrowthTree"
	end
	function Factory.validate(model)
		assert(Factory.isTree(model), "Select a Bora growth tree")
		assert(model:GetAttribute("SchemaVersion") == 3, "This is a v2 tree. Place a new v3 tree to use the connected wood mesh.")
		assert(model:FindFirstChild("Root") and model.Root:IsA("BasePart"), "Tree root is missing")
		local g = model:FindFirstChild("Geometry")
		assert(g and g:FindFirstChild("Trunk") and g.Trunk:FindFirstChild("Geometry"), "Tree wood is missing")
		assert(g:FindFirstChild("Leaves") and #g.Leaves:GetChildren() == cardCount, "Generated foliage was modified")
	end
	function Factory.setGrowth(model, value)
		Factory.validate(model)
		local layout = Factory.layout(value, model:GetAttribute("Seed") or 42)
		local base = model.Root.CFrame
		local function update(p, item)
			p.CFrame = base * item.Frame
			p.Size = Vector3.new(math.max(.05, item.Size.X), math.max(.05, item.Size.Y), math.max(.02, item.Size.Z))
			if p:FindFirstChild("Geometry") then p.Geometry.Scale = item.Scale end
		end
		update(model.Geometry.Trunk, layout.Trunk)
		for i, item in layout.Leaves do
			local p = model.Geometry.Leaves:FindFirstChild("Leaves" .. i)
			assert(p, "Generated leaf card is missing")
			update(p, item)
			for _, face in { "Front", "Back" } do
				p[face].Foliage.ImageColor3 = Color3.new(item.Tint,item.Tint,item.Tint)
			end
		end
		-- Collision covers the lower trunk; crown limbs remain decorative.
		model.Collision.Size = Vector3.new(layout.Dimensions.Diameter, layout.Dimensions.Height*.42, layout.Dimensions.Diameter)
		model.Collision.CFrame = base * CFrame.new(0, model.Collision.Size.Y/2, 0)
		model:SetAttribute("Growth", layout.Dimensions.Growth)
	end
	function Factory.create(config, transform)
		local model = Instance.new("Model")
		model.Name = "은행나무"
		model:SetAttribute("AssetKind", "BoraGrowthTree")
		model:SetAttribute("SchemaVersion", 3)
		model:SetAttribute("Species", "Ginkgo")
		model:SetAttribute("Seed", config.Seed or 42)
		model:SetAttribute("ObjectId", config.ObjectId)
		model:SetAttribute("AssetSource", "Blender connected skeleton / OpenAI foliage")
		local root = part(model, "Root")
		root.Size, root.Transparency, root.CFrame = Vector3.new(.1,.1,.1), 1, transform or CFrame.new()
		model.PrimaryPart = root
		local collision = part(model,"Collision")
		collision.Transparency, collision.CanCollide = 1, true
		local geometry = Instance.new("Folder")
		geometry.Name, geometry.Parent = "Geometry", model
		local wood = part(geometry,"Trunk")
		wood.CanQuery = true
		local mesh = Instance.new("SpecialMesh")
		mesh.Name, mesh.MeshType = "Geometry", Enum.MeshType.FileMesh
		mesh.MeshId, mesh.TextureId, mesh.Parent = catalog.Wood.Mesh, catalog.Wood.Texture, wood
		local leaves = Instance.new("Folder")
		leaves.Name, leaves.Parent = "Leaves", geometry
		for i = 1, cardCount do leafCard(leaves,"Leaves"..i) end
		Factory.setGrowth(model, config.Growth or 0)
		return model
	end
	return Factory
end
