-- Emit only a neighborhood model and a local geometry preview, never a Place.
return function()
	local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
	local V,C=r.Vector3,r.CFrame;local S=1/.28
	local place=r.deserializePlace(fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*',''))
	local world=place:GetService('Workspace');local roads=world.BoraRoads
	local Path=require('../src/RoadPath')(V)
	local Roads=require('../src/RoadNetworkFactory')(r,Path)
	local J=require('../src/RoadJunctions')(V,Path)
	local Traffic=require('../src/RoadTraffic')(r,Path,nil,require('../src/TrafficAssetLayout'))
	local data={};local all={}
	for _,road in roads:GetChildren() do if Roads.isRoad(road) then
		local d=Path.sample(Roads.points(road),Roads.config(road));data[road]=d;table.insert(all,d)
	end end
	local selected
	for _,junction in roads.Junctions:GetChildren() do
		if junction:GetAttribute('ArmCount')==4 and (not selected or junction.Name<selected.Name) then selected=junction end
	end
	assert(selected,'A saved four-arm junction is required; do not create or move existing roads.')
	local approaches={}
	for _,ref in selected.Members:GetChildren() do
		table.insert(approaches,{Data=data[ref.Value],At=ref:GetAttribute('At'),End=ref:GetAttribute('Endpoint')})
	end
	local junction=J.planApproaches(approaches)
	local center=junction.Center;local ground=center.Y+.12*S
	local function nearest(d,p)
		local best,q=math.huge,nil
		for i=1,#d.Samples-1 do
			local a,b=d.Samples[i].P,d.Samples[i+1].P
			local delta=V.new(b.X-a.X,0,b.Z-a.Z);local v=V.new(p.X-a.X,0,p.Z-a.Z)
			local t=math.clamp(v:Dot(delta)/delta:Dot(delta),0,1)
			local point=a+delta*t;local distance=V.new(p.X-point.X,0,p.Z-point.Z).Magnitude
			if distance<best then best,q=distance,point end
		end
		return best,q
	end
	local function clear(frame,w,d,apron)
		local minimum=math.huge
		for x=-w*.5-.7,w*.5+.7,.6 do
			for _,z in {-d*.5-apron,d*.5} do
				local p=frame:PointToWorldSpace(V.new(x*S,0,z*S))
				for _,road in all do
					local distance=nearest(road,p)/S-(road.Config.Width*.5+road.Config.Sidewalk)
					minimum=math.min(minimum,distance)
				end
			end
		end
		for z=-d*.5-apron,d*.5,.6 do for _,x in {-w*.5-.7,w*.5+.7} do
			local p=frame:PointToWorldSpace(V.new(x*S,0,z*S))
			for _,road in all do minimum=math.min(minimum,nearest(road,p)/S-(road.Config.Width*.5+road.Config.Sidewalk)) end
		end end
		return minimum
	end
	local specs={
		{Id='SlowCoffee',Kind='Cafe',Title='느린 커피',Floors=2,Width=11.4,Depth=8.6,Wall={210,202,181},Trim={228,223,207},Accent={71,103,92}},
		{Id='BoraPharmacy',Kind='Pharmacy',Title='보라 약국',Floors=3,Width=12.6,Depth=9.6,Wall={214,214,201},Trim={235,232,217},Accent={70,107,84}},
		{Id='BoraMarket',Kind='Market',Title='보라 마트',Floors=2,Width=13.2,Depth=9.8,Wall={156,109,84},Trim={208,194,171},Accent={55,75,91}},
		{Id='BoraVilla',Kind='Residential',Title='보라빌라  101',Floors=3,Width=10.8,Depth=9.4,Wall={189,182,163},Trim={220,214,197},Accent={88,97,91}},
	}
	local plan={Junction=selected.Name,Center=center,Plots={},Lamps={},Landings={}}
	for i,spec in specs do
		local a,b=junction.Arms[i],junction.Arms[i%4+1]
		local bisector=(a.Direction+b.Direction).Unit
		local found
		for distance=20,43,1 do
			local p=V.new(center.X,ground,center.Z)+bisector*(distance*S)
			local road=a.Data
			local edge,q=nearest(road,p);q=V.new(q.X,ground,q.Z)
			local frame=C.lookAt(p,q)
			local apron=edge/S-spec.Depth*.5-(road.Config.Width*.5+road.Config.Sidewalk+.06)
			if apron>2.8 and apron<16 then
				-- Move the forecourt edge back slightly on a curved approach.
				for back=0,1.2,.1 do
					local clearance=clear(frame,spec.Width,spec.Depth,apron-back)
					if clearance>=-.025 then
						found=table.clone(spec);found.Frame=frame;found.Apron=apron-back;found.SidewalkClearance=clearance
						found.CenterDistance=distance;break
					end
				end
			end
			if found then break end
		end
		assert(found,'No clear building plot for '..spec.Id)
		table.insert(plan.Plots,found)
	end
	local settings=Traffic.config(roads)
	for _,arm in junction.Arms do
		for _,side in {-1,1} do
			local sample=Path.at(arm.Data,arm.Anchor+arm.Sign*(arm.Trim+(settings.CrosswalkOffset+settings.CrosswalkWidth*.5)*S))
			local outward=sample.Side*arm.Sign*side
			local p=sample.P+outward*(arm.Half+.48*S)
			table.insert(plan.Landings,{Position=V.new(p.X,ground,p.Z),Direction=-outward.Unit})
			local s=Path.at(arm.Data,arm.Anchor+arm.Sign*(arm.Trim+11*S))
			local q=s.P+s.Side*(arm.Sign*side)*(arm.Half+arm.Walk+.45*S)
			table.insert(plan.Lamps,{Position=V.new(q.X,ground,q.Z),Direction=-s.Side*(arm.Sign*side)})
		end
	end
	local root=require('../src/NeighborhoodFactory')(r).create(plan)
	fs.writeFile('dist/BoraNeighborhood.rbxmx',r.serializeModel({root},true))
	local preview=r.Instance.new('Model');preview.Name='NeighborhoodPreview';root:Clone().Parent=preview
	local context=r.Instance.new('Model');context.Name='ExistingRoads';context.Parent=preview
	local count=0
	for _,item in roads:GetDescendants() do
		if item:IsA('BasePart') and (item.CFrame.Position-center).Magnitude<230 and item.Transparency<1 then
			local copy=item:Clone()
			for _,n in copy:GetDescendants() do if n:IsA('JointInstance') or n:IsA('WeldConstraint') then n:Destroy() end end
			copy.Parent=context;count+=1
		end
	end
	fs.writeFile('dist/NeighborhoodPreview.rbxmx',r.serializeModel({preview},true))
	local plots={}
	for _,p in plan.Plots do
		table.insert(plots,{Id=p.Id,Kind=p.Kind,Title=p.Title,Floors=p.Floors,Width=p.Width,Depth=p.Depth,Apron=p.Apron,
			Position={p.Frame.X,p.Frame.Y,p.Frame.Z},Look={p.Frame.LookVector.X,p.Frame.LookVector.Y,p.Frame.LookVector.Z},Clearance=p.SidewalkClearance})
	end
	local parts=0
	for _,p in root:GetDescendants() do if p:IsA('BasePart') then parts+=1 end end
	fs.writeFile('dist/neighborhood-plan.json',serde.encode('json',{Revision=1,Junction=selected.Name,Center={center.X,center.Y,center.Z},Plots=plots,
		Buildings=#plots,Lamps=#plan.Lamps,TactileLandings=#plan.Landings,Parts=parts,ContextParts=count,StudsPerMeter=S},true))
	print('Staged neighborhood at '..selected.Name..': '..#plots..' buildings, '..parts..' new editable parts. Ro.rbxlx unchanged.')
end
