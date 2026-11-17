return function(api,Path,Traffic)
	local Instance,Vector3,CFrame,Color3,Enum=api.Instance,api.Vector3,api.CFrame,api.Color3,api.Enum
	local Factory={}
	local function part(parent,class,name,size,frame,color,material,preview)
		local p=Instance.new(class)
		p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,frame,color,material
		p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,not preview,false,not preview
		p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
		if preview then p.Transparency=.4; p.Color=Color3.fromRGB(70,190,171) end
		p.Parent=parent
		return p
	end
	local function triangle(parent,a,b,c,thickness,color,material,preview)
		local ab,ac,bc=b-a,c-a,c-b
		local abd,acd,bcd=ab:Dot(ab),ac:Dot(ac),bc:Dot(bc)
		if abd>acd and abd>bcd then c,a=a,c elseif acd>abd and acd>bcd then a,b=b,a end
		ab,ac,bc=b-a,c-a,c-b
		local normal=ac:Cross(ab)
		assert(normal.Magnitude>1e-7,'도로 표면이 겹칩니다. 코너를 완만하게 바꾸세요.')
		if normal.Y<0 then b,c=c,b; ab,ac,bc=b-a,c-a,c-b; normal=ac:Cross(ab) end
		local right=normal.Unit
		local up=bc:Cross(right).Unit
		local back=bc.Unit
		local height=math.abs(ab:Dot(up))
		for _,piece in {{(a+b)*.5,right,up,back,math.abs(ab:Dot(back))},{(a+c)*.5,-right,up,-back,math.abs(ac:Dot(back))}} do
			if piece[5]>.001 and height>.001 then
				part(parent,'WedgePart','Surface',Vector3.new(thickness,height,piece[5]),
					CFrame.fromMatrix(piece[1]-right*thickness*.5,piece[2],piece[3],piece[4]),color,material,preview)
			end
		end
	end
	local function strip(parent,a,b,left,right,height,thickness,color,material,preview)
		local lift=Vector3.new(0,height,0)
		local p,q,r,s=Path.offset(a,left)+lift,Path.offset(a,right)+lift,Path.offset(b,right)+lift,Path.offset(b,left)+lift
		triangle(parent,p,q,r,thickness,color,material,preview)
		triangle(parent,p,r,s,thickness,color,material,preview)
	end
	function Factory.isRoad(model)
		return model and model:IsA('Model') and model:GetAttribute('AssetKind')=='BoraRoadPath'
	end
	function Factory.points(model)
		assert(Factory.isRoad(model),'도로를 선택하세요.')
		local folder=assert(model:FindFirstChild('Nodes'),'도로 점이 없습니다.')
		local nodes=folder:GetChildren()
		table.sort(nodes,function(a,b) return a:GetAttribute('Index')<b:GetAttribute('Index') end)
		local points={}; for _,node in nodes do table.insert(points,node.Value) end
		return points
	end
	function Factory.config(model)
		local values={}; for key in Path.Defaults do values[key]=model:GetAttribute(key) end
		return Path.normalize(values)
	end
	local function stage(points,input,preview,cuts,markingCuts)
		local data=Path.sample(points,input)
		local config=data.Config
		local geometry=Instance.new('Folder'); geometry.Name='Geometry'
		local nodes=Instance.new('Folder'); nodes.Name='Nodes'
		local ok,err=pcall(function()
			for i,p in points do
				local node=Instance.new('Vector3Value'); node.Name=string.format('Point%03d',i)
				node.Value,node.Parent=p,nodes; node:SetAttribute('Index',i)
			end
			local asphalt=Instance.new('Folder'); asphalt.Name,asphalt.Parent='Asphalt',geometry
			local sidewalks=Instance.new('Folder'); sidewalks.Name,sidewalks.Parent='Sidewalks',geometry
			local markings=Instance.new('Folder'); markings.Name,markings.Parent='Markings',geometry
			local width,walk,lift=config.Width*Path.StudsPerMeter,config.Sidewalk*Path.StudsPerMeter,config.Lift*Path.StudsPerMeter
			for _,segment in Path.segments(data,cuts) do
				local a,b=segment[1],segment[2]
				strip(asphalt,a,b,-width*.5,width*.5,lift,.6,Color3.fromRGB(57,60,65),Enum.Material.Asphalt,preview)
				if walk>0 then
					for _,side in {-1,1} do
						strip(sidewalks,a,b,side*width*.5,side*(width*.5+walk),lift+.12*Path.StudsPerMeter,.7,Color3.fromRGB(170,172,166),Enum.Material.Concrete,preview)
					end
				end
			end
			local allCuts={}
			for _,set in {cuts or {},markingCuts or {}} do for _,cut in set do table.insert(allCuts,{cut[1],cut[2]}) end end
			table.sort(allCuts,function(a,b) return a[1]<b[1] end)
			local merged={}
			for _,cut in allCuts do
				local last=merged[#merged]
				if last and cut[1]<=last[2] then last[2]=math.max(last[2],cut[2]) else table.insert(merged,cut) end
			end
			if not preview then
				for _,segment in Path.segments(data,merged) do
					local a,b=segment[1],segment[2]
					for lane=1,config.Lanes-1 do
						local isCenter=lane==math.floor(config.Lanes/2)
						if isCenter or math.floor((a.Distance+b.Distance)*.5/14)%2==0 then
							local offset=-width*.5+width*lane/config.Lanes
							local p,q=Path.offset(a,offset),Path.offset(b,offset)
							local delta=q-p
							local mark=part(markings,'Part',if isCenter then 'CenterLine' else 'LaneLine',Vector3.new(.12*Path.StudsPerMeter,.025,delta.Magnitude+.025),
								CFrame.lookAt((p+q)*.5+Vector3.new(0,lift+.025,0),q+Vector3.new(0,lift+.025,0)),
								if isCenter then Color3.fromRGB(239,189,60) else Color3.fromRGB(236,237,224),Enum.Material.SmoothPlastic,false)
							mark.CanCollide,mark.CanQuery=false,false
						end
					end
				end
			end
		end)
		if not ok then geometry:Destroy(); nodes:Destroy(); error(err) end
		return geometry,nodes,data
	end
	function Factory.prepare(points,config,cuts,markingCuts)
		local geometry,nodes,data=stage(points,config,false,cuts,markingCuts)
		return {Geometry=geometry,Nodes=nodes,Data=data,PointCount=#points}
	end
	function Factory.commit(model,prepared)
		assert(Factory.isRoad(model),'도로를 선택하세요.')
		local geometry,nodes,data=prepared.Geometry,prepared.Nodes,prepared.Data
		for _,name in {'Geometry','Nodes'} do
			local old=model:FindFirstChild(name)
			if old then old.Name='Previous'..name; if api.Retire then api.Retire(old) else old:Destroy() end end
		end
		geometry.Parent,nodes.Parent=model,model
		for key,value in data.Config do model:SetAttribute(key,value) end
		model:SetAttribute('LengthMeters',data.Length/Path.StudsPerMeter)
		model:SetAttribute('NodeCount',prepared.PointCount)
		model:SetAttribute('RoadSchemaVersion',1)
		return model
	end
	function Factory.rebuild(model,points,config)
		return Factory.commit(model,Factory.prepare(points,config))
	end
	function Factory.junction(plan)
		local model=Instance.new('Model'); model.Name='TJunction'
		model:SetAttribute('AssetKind','BoraRoadJunction')
		local asphalt=Instance.new('Folder'); asphalt.Name,asphalt.Parent='Asphalt',model
		local walks=Instance.new('Folder'); walks.Name,walks.Parent='Sidewalks',model
		local ok,err=pcall(function()
			for i,p in plan.Perimeter do
				local q=plan.Perimeter[i%#plan.Perimeter+1]
				if (p-plan.Center):Cross(q-plan.Center).Magnitude>.00001 then
					triangle(asphalt,plan.Center,p,q,.6,Color3.fromRGB(57,60,65),Enum.Material.Asphalt,false)
				end
			end
			local lift=Vector3.yAxis*(.12*Path.StudsPerMeter)
			for _,band in plan.Bands do
				local a,b,c,d=band[1]+lift,band[2]+lift,band[3]+lift,band[4]+lift
				if (b-a):Cross(c-a).Magnitude>.00001 then triangle(walks,a,b,c,.7,Color3.fromRGB(170,172,166),Enum.Material.Concrete,false) end
				if (c-a):Cross(d-a).Magnitude>.00001 then triangle(walks,a,c,d,.7,Color3.fromRGB(170,172,166),Enum.Material.Concrete,false) end
			end
			if plan.Traffic then
				local marks=Instance.new('Folder'); marks.Name,marks.Parent='Markings',model
				for _,mark in plan.Traffic.Markings do
					local group=Instance.new('Folder'); group.Name,group.Parent=mark.Kind,marks; group:SetAttribute('Arm',mark.Arm)
					if mark.Lane then group:SetAttribute('Lane',mark.Lane); group:SetAttribute('Directions',mark.Mask) end
					local p=mark.Corners
					triangle(group,p[1],p[2],p[3],.025,Color3.fromRGB(241,241,228),Enum.Material.SmoothPlastic,false)
					if p[4] then triangle(group,p[1],p[3],p[4],.025,Color3.fromRGB(241,241,228),Enum.Material.SmoothPlastic,false) end
					for _,piece in group:GetChildren() do piece.CanCollide,piece.CanQuery=false,false end
				end
				if Traffic then Traffic.buildSignals(model,plan) end
			end
		end)
		if not ok then model:Destroy(); error(err) end
		return model
	end
	function Factory.create(points,config,id)
		local model=Instance.new('Model'); model.Name=utf8.char(0xB3C4,0xB85C)
		model:SetAttribute('AssetKind','BoraRoadPath'); model:SetAttribute('ObjectId',id)
		local ok,err=pcall(Factory.rebuild,model,points,config)
		if not ok then model:Destroy(); error(err) end
		return model
	end
	function Factory.preview(points,config)
		local geometry,nodes=stage(points,config,true)
		nodes:Destroy(); return geometry
	end
	return Factory
end
