return function(api,rules,catalog,Parameters,Skeleton,Mesher)
	local Instance,Vector3,CFrame,Enum,Color3,UDim2=api.Instance,api.Vector3,api.CFrame,api.Enum,api.Color3,api.UDim2
	local Factory={}
	local function part(parent,name)
		local p=Instance.new("Part")
		p.Name,p.Anchored=name,true
		p.CanCollide,p.CanTouch,p.CanQuery=false,false,false
		p.Material,p.Color=Enum.Material.SmoothPlastic,Color3.new(1,1,1)
		p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
		p.Parent=parent
		return p
	end
	function Factory.foliage(skeleton)
		local config=skeleton.Config
		local leaves={}
		local state=config.Seed+17
		local function random() state=state*48271%2147483647; return state/2147483647 end
		local cards=math.floor(#skeleton.Anchors*3*config.LeafDensity+.5)
		for i=1,cards do
			local anchor=skeleton.Anchors[(i-1)%#skeleton.Anchors+1]
			local size=4.3*(.88+random()*.26)
			local tier=math.floor((i-1)/#skeleton.Anchors)%3
			local center=if tier==2 then anchor*Vector3.new(.78,1,.78) else anchor
			center+=Vector3.new((random()-.5)*size*.75,(random()-.5)*size*.48,(random()-.5)*size*.75)
			local tilt=if tier==2 then math.rad(48+random()*25) else math.rad(-42+random()*84)
			local rotation=CFrame.Angles(0,random()*math.pi*2,0)*CFrame.Angles(tilt,0,math.rad(-17+random()*34))
			table.insert(leaves,{Center=center,Rotation=rotation,Size=Vector3.new(size,size*(.83+random()*.13),.02),Tint=.91+random()*.09})
		end
		return leaves
	end
	local function makeCard(parent,name,item)
		local p=part(parent,name)
		p.Transparency,p.CastShadow=1,false
		p:SetAttribute("BaseCenter",item.Center)
		p:SetAttribute("BaseSize",item.Size)
		p:SetAttribute("BaseRotation",item.Rotation)
		for _,face in {Enum.NormalId.Front,Enum.NormalId.Back} do
			local gui=Instance.new("SurfaceGui")
			gui.Name,gui.Face,gui.AlwaysOnTop,gui.LightInfluence=face.Name,face,false,1
			gui.SizingMode,gui.PixelsPerStud,gui.MaxDistance=Enum.SurfaceGuiSizingMode.PixelsPerStud,96,300
			gui.Active,gui.Parent=false,p
			local image=Instance.new("ImageLabel")
			image.Name,image.Image="Foliage",catalog.Leaf.Texture
			image.BackgroundTransparency,image.Size=1,UDim2.fromScale(1,1)
			image.ImageColor3=Color3.new(item.Tint,item.Tint,item.Tint)
			image.Parent=gui
		end
	end
	function Factory.isTree(model)
		return model and model:IsA("Model") and model:GetAttribute("AssetKind")=="BoraGrowthTree"
	end
	function Factory.validate(model)
		assert(Factory.isTree(model) and model:GetAttribute("SchemaVersion")==4,"Select a procedural tree")
		assert(model:GetAttribute("RecipeVersion")==Parameters.Version,"Unsupported tree recipe version")
		assert(model:FindFirstChild("Root") and model.Root:IsA("BasePart"),"Tree root is missing")
		local g=model:FindFirstChild("Geometry")
		assert(g and g:FindFirstChild("Wood") and #g.Wood:GetChildren()>0 and g:FindFirstChild("Leaves"),"Tree geometry is missing")
		Parameters.fromModel(model)
	end
	function Factory.setGrowth(model,value)
		Factory.validate(model)
		local d=rules.dimensions(value)
		local scale=Vector3.new(d.Diameter/2.2,d.Height/18,d.Diameter/2.2)
		local base=model.Root.CFrame
		for _,p in model.Geometry.Wood:GetChildren() do
			p.CFrame=base*CFrame.new(p:GetAttribute("BaseCenter")*scale)
			local size=p:GetAttribute("BaseSize")*scale
			p.Size=Vector3.new(math.max(.001,size.X),math.max(.001,size.Y),math.max(.001,size.Z))
			if p:FindFirstChild("Geometry") then p.Geometry.Scale=scale end
		end
		local leafScale=d.LeafSize/4.3
		for _,p in model.Geometry.Leaves:GetChildren() do
			p.CFrame=base*CFrame.new(p:GetAttribute("BaseCenter")*scale)*p:GetAttribute("BaseRotation")
			local s=p:GetAttribute("BaseSize")*leafScale
			p.Size=Vector3.new(s.X,s.Y,.02)
		end
		model.Collision.Size=Vector3.new(d.Diameter*model:GetAttribute("Thickness"),d.Height*.42,d.Diameter*model:GetAttribute("Thickness"))
		model.Collision.CFrame=base*CFrame.new(0,model.Collision.Size.Y/2,0)
		model:SetAttribute("Growth",d.Growth)
	end
	local function stage(config,progress)
		local skeleton=Skeleton.build(config)
		local data=Mesher.build(skeleton,{Progress=progress})
		local geometry=Instance.new("Folder"); geometry.Name="Geometry"
		local ok,err=pcall(function()
			local wood=Instance.new("Folder"); wood.Name,wood.Parent="Wood",geometry
			local pieces=api.BuildWood(data,config)
			for _,p in pieces do p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,false,false,true; p.Parent=wood end
			local leaves=Instance.new("Folder"); leaves.Name,leaves.Parent="Leaves",geometry
			for i,item in Factory.foliage(skeleton) do makeCard(leaves,"Leaves"..i,item) end
		end)
		if not ok then geometry:Destroy(); error(err) end
		return geometry,data,skeleton
	end
	function Factory.rebuild(model,input,progress)
		assert(Factory.isTree(model) and model:FindFirstChild("Root") and model:FindFirstChild("Collision"),"Select a Bora tree")
		local config=Parameters.normalize(input)
		local growth=rules.normalize(model:GetAttribute("Growth") or 1)
		local geometry,data=stage(config,progress)
		if not model:FindFirstChild("Root") or not model:FindFirstChild("Collision") then geometry:Destroy(); error("Tree removed during generation") end
		local old=model:FindFirstChild("Geometry")
		-- Commit after all asynchronous mesh work succeeds. Root and ObjectId stay intact.
		if old then old.Name="PreviousGeometry" end
		geometry.Parent=model
		for name,value in config do model:SetAttribute(name,value) end
		model:SetAttribute("SchemaVersion",4)
		model:SetAttribute("RecipeVersion",Parameters.Version)
		model:SetAttribute("LiveMesh",api.LiveMesh~=false)
		model:SetAttribute("WoodTriangles",#data.Faces)
		model:SetAttribute("BranchGraphCount",config.BranchCount*3+1)
		model:SetAttribute("AssetSource","Procedural smooth union / OpenAI foliage")
		Factory.setGrowth(model,growth)
		if old then
			if api.RetireGeometry then api.RetireGeometry(old) else old:Destroy() end
		end
		return model
	end
	function Factory.create(input,transform,progress)
		local config=Parameters.normalize(input)
		local growth=rules.normalize(if input.Growth==nil then 0 else input.Growth)
		local model=Instance.new("Model")
		model.Name="은행나무"
		model:SetAttribute("AssetKind","BoraGrowthTree")
		model:SetAttribute("Species","Ginkgo")
		model:SetAttribute("Growth",growth)
		model:SetAttribute("ObjectId",input.ObjectId)
		local root=part(model,"Root")
		root.Size,root.Transparency,root.CFrame=Vector3.new(.1,.1,.1),1,transform or CFrame.new()
		model.PrimaryPart=root
		local collision=part(model,"Collision")
		collision.Transparency,collision.CanCollide=1,true
		local ok,err=pcall(Factory.rebuild,model,config,progress)
		if not ok then model:Destroy(); error(err) end
		return model
	end
	return Factory
end
