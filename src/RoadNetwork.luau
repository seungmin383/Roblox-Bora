return function(api,Path,Roads,Junctions,Traffic,LaneDirections)
	local Instance,Vector3=api.Instance,api.Vector3
	local Network={}
	local function retire(item)
		if api.Retire then api.Retire(item) else item:Destroy() end
	end
	function Network.links(road)
		local links={}; local folder=road:FindFirstChild('JunctionLinks')
		if folder then
			for _,ref in folder:GetChildren() do
				if ref:IsA('ObjectValue') and Roads.isRoad(ref.Value) and ref.Value.Parent then
					table.insert(links,{Host=ref.Value,At=ref:GetAttribute('At'),End=ref.Name})
				end
			end
		end
		return links
	end
	function Network.snap(folder,p,current,limit)
		local best,target,link=limit or 8,p,nil
		if not folder then return target end
		-- Reuse the host of a saved hub when adding the opposite T arm. A
		-- branch-to-branch attachment would otherwise produce overlapping patches.
		local junctions=folder:FindFirstChild('Junctions')
		if junctions then for _,junction in junctions:GetChildren() do
			local ref=junction:FindFirstChild('Host'); local at=junction:GetAttribute('At')
			local host=if ref and ref:IsA('ObjectValue') then ref.Value else nil
			if Roads.isRoad(host) and host.Parent==folder and host~=current and type(at)=='number' then
				local data=Path.sample(Roads.points(host),Roads.config(host))
				local q=Path.at(data,data.Length*at).P
				local delta=Vector3.new(p.X-q.X,0,p.Z-q.Z).Magnitude
				if delta<best and math.abs(q.Y-p.Y)<3 then best,target,link=delta,q,{Host=host,At=at} end
			end
		end end
		if link then return target,link end
		for _,road in folder:GetChildren() do if Roads.isRoad(road) and road~=current then
			local data=Path.sample(Roads.points(road),Roads.config(road))
			local q,distance,delta=Path.project(data,p)
			if distance<8 or distance>data.Length-8 then
				distance=if distance<8 then 0 else data.Length
				q=Path.at(data,distance).P
				delta=Vector3.new(p.X-q.X,0,p.Z-q.Z).Magnitude
			end
			if delta<best and math.abs(q.Y-p.Y)<3 then
				best,target=delta,q
				link=if distance>1 and distance<data.Length-1 then {Host=road,At=distance/data.Length} else nil
			end
		end end
		return target,link
	end
	function Network.attachEnds(folder,points,current)
		local list,links=table.clone(points),{}
		for _,index in {1,#points} do
			local p,link=Network.snap(folder,points[index],current)
			list[index]=p
			if link then link.End=if index==1 then 'Start' else 'End'; table.insert(links,link) end
		end
		return list,links
	end
	local function samePoints(a,b)
		if #a~=#b then return false end
		for i,p in a do if (p-b[i]).Magnitude>.00001 then return false end end
		return true
	end
	-- Plan/stage everything before touching saved objects, then commit in the
	-- caller's single ChangeHistory recording. A rejected junction changes nothing.
	function Network.apply(folder,changed,points,config,links,trafficInput,laneInput)
		local previous=folder:FindFirstChild('Junctions')
		assert(not previous or previous:GetAttribute('AssetKind')=='BoraRoadJunctions','Junctions 이름의 사용자 폴더가 있습니다.')
		local states,order={},{ }
		for _,road in folder:GetChildren() do if Roads.isRoad(road) then
			local state={Road=road,Original=Roads.points(road),Config=Roads.config(road),Links=Network.links(road),Cuts={},MarkingCuts={},ReservedCuts={}}
			state.Points=table.clone(state.Original); states[road]=state; table.insert(order,state)
		end end
		assert(#order<=256,'도로가 256개를 넘습니다. 구역 분리 지원이 필요합니다.')
		if changed then
			local state=assert(states[changed],'도로가 도로 폴더 밖에 있습니다.')
			state.Points,state.Config=table.clone(points),Path.normalize(config)
			if links then state.Links=links end
		end
		local function resolve(state)
			if state.Data then return end
			assert(not state.Resolving,'순환 연결은 아직 지원하지 않습니다. 한쪽 연결을 분리하세요.')
			state.Resolving=true
			local occupied={}
			for _,link in state.Links do
				assert(link.End=='Start' or link.End=='End','잘못된 연결 끝점입니다.')
				assert(not occupied[link.End],'한 끝점에는 연결 하나만 가능합니다.'); occupied[link.End]=true
				assert(type(link.At)=='number' and link.At>0 and link.At<1,'잘못된 교차로 위치입니다.')
				local host=assert(states[link.Host],'연결 대상 도로가 없습니다.')
				resolve(host)
				local p=Path.at(host.Data,host.Data.Length*link.At).P
				state.Points[if link.End=='Start' then 1 else #state.Points]=p+Vector3.yAxis*((host.Config.Lift-state.Config.Lift)*Path.StudsPerMeter)
			end
			state.Data=Path.sample(state.Points,state.Config); state.Resolving=false
		end
		for _,state in order do resolve(state) end
		local groups={}
		local function anchor(approach)
			return if approach.End=='Start' then 0 elseif approach.End=='End' then approach.Data.Length else approach.At*approach.Data.Length
		end
		local function findGroup(state,distance)
			for _,group in groups do for _,approach in group do
				if approach.State==state and math.abs(anchor(approach)-distance)<.05 then return group end
			end end
		end
		local function add(group,state,at,endpoint)
			for _,approach in group do
				if approach.State==state then
					assert(approach.End==endpoint,'한 도로가 같은 교차로에 중복 진입합니다.')
					return
				end
			end
			table.insert(group,{State=state,Data=state.Data,At=at,End=endpoint})
		end
		for _,state in order do for _,link in state.Links do
			local host=states[link.Host]
			local group=findGroup(host,link.At*host.Data.Length)
			if not group then group={}; table.insert(groups,group); add(group,host,link.At) end
			add(group,state,nil,link.End)
		end end
		-- Interior crossings are derived from the sampled centerlines. Both
		-- roads retain their editable nodes and are rebuilt together after edits.
		for i,a in order do for j=i+1,#order do
			local b=order[j]
			for _,hit in Path.crossings(a.Data,b.Data) do
				local ga,gb=findGroup(a,hit.A),findGroup(b,hit.B)
				local group=ga or gb
				if ga and gb and ga~=gb then
					for _,approach in gb do add(ga,approach.State,approach.At,approach.End) end
					for k,candidate in groups do if candidate==gb then table.remove(groups,k); break end end
				end
				if not group then group={}; table.insert(groups,group) end
				add(group,a,hit.A/a.Data.Length); add(group,b,hit.B/b.Data.Length)
			end
		end end
		local planned,stats={},{T=0,Cross=0,Limited=0,LimitedArrows=0}
		local trafficSettings=if Traffic then (if trafficInput then Traffic.normalize(trafficInput) else Traffic.config(folder)) else nil
		for _,group in groups do
			local plan=Junctions.planApproaches(group)
			plan.Host,plan.Branch=group[1].State.Road,group[2].State.Road
			plan.End,plan.At=group[2].End or 'Cross',group[1].At
			for i,approach in group do table.insert(approach.State.Cuts,plan.Cuts[i]) end
			local kind=if #plan.Arms==4 then 'Cross' else 'T'; stats[kind]+=1
			table.insert(planned,plan)
		end
		for _,state in order do Junctions.checkCuts(state.Cuts) end
		local laneSerial=folder:GetAttribute('LaneSerial') or 0
		if LaneDirections then laneSerial=LaneDirections.bind(planned,previous,laneSerial,laneInput) end
		if Traffic then
			for _,plan in planned do
				local group=plan.Approaches
				for _,arm in plan.Arms do
					local portal=arm.Anchor+arm.Sign*arm.Trim
					local room=math.huge
					for _,cut in group[arm.Approach].State.Cuts do
						if cut~=plan.Cuts[arm.Approach] then
							local gap=if arm.Sign==1 then cut[1]-portal else portal-cut[2]
							if gap>0 then room=math.min(room,gap*.5-1) end
						end
					end
					arm.TrafficRoom=room
				end
				local decoration=Traffic.plan(plan,trafficSettings)
				stats.Limited+=decoration.Limited
				stats.LimitedArrows+=decoration.LimitedArrows or 0
				local reserved={}; for i,cut in plan.Cuts do reserved[i]={cut[1],cut[2]} end
				for _,cut in decoration.Cuts do
					table.insert(group[cut.Approach].State.MarkingCuts,cut.Range)
					local range=reserved[cut.Approach]; range[1],range[2]=math.min(range[1],cut.Range[1]),math.max(range[2],cut.Range[2])
				end
				for i,approach in group do table.insert(approach.State.ReservedCuts,reserved[i]) end
			end
		end
		for _,state in order do Junctions.checkCuts(state.Cuts); Junctions.checkCuts(state.ReservedCuts) end
		local staged={}; local junctionFolder=Instance.new('Folder'); junctionFolder.Name='Junctions'
		junctionFolder:SetAttribute('AssetKind','BoraRoadJunctions')
		local ok,err=pcall(function()
			for _,state in order do
				if state.Road==changed or #state.Cuts>0 or state.Road:GetAttribute('JunctionCut') or not samePoints(state.Points,state.Original) then
					state.Prepared=Roads.prepare(state.Points,state.Config,state.Cuts,state.MarkingCuts); table.insert(staged,state)
				end
			end
			for i,plan in planned do
				local model=Roads.junction(plan); model.Name=(if #plan.Arms==4 then 'XJunction_' else 'TJunction_')..i
				model.Parent=junctionFolder
				model:SetAttribute('Endpoint',plan.End); model:SetAttribute('At',plan.At)
				model:SetAttribute('ArmCount',#plan.Arms); model:SetAttribute('Center',plan.Center)
				if plan.Traffic then model:SetAttribute('LimitedApproaches',plan.Traffic.Limited) end
				if LaneDirections then LaneDirections.write(model,plan) end
				for key,road in {Host=plan.Host,Branch=plan.Branch} do local ref=Instance.new('ObjectValue'); ref.Name,ref.Value,ref.Parent=key,road,model end
				local members=Instance.new('Folder'); members.Name='Members'; members.Parent=model
				for n,approach in plan.Approaches do
					local ref=Instance.new('ObjectValue'); ref.Name,ref.Value='Road'..n,approach.State.Road
					ref:SetAttribute('At',approach.At); ref:SetAttribute('Endpoint',approach.End); ref.Parent=members
				end
				model.Parent=junctionFolder
			end
		end)
		if not ok then
			for _,state in staged do state.Prepared.Geometry:Destroy(); state.Prepared.Nodes:Destroy() end
			junctionFolder:Destroy(); error(err)
		end
		for _,state in staged do
			Roads.commit(state.Road,state.Prepared)
			state.Road:SetAttribute('JunctionCut',if #state.Cuts>0 then true else nil)
		end
		if changed and links then
			local old=changed:FindFirstChild('JunctionLinks'); if old then retire(old) end
			local saved=Instance.new('Folder'); saved.Name='JunctionLinks'
			for _,link in links do
				local ref=Instance.new('ObjectValue'); ref.Name,ref.Value=link.End,link.Host
				ref:SetAttribute('At',link.At); ref.Parent=saved
			end
			saved.Parent=changed
		end
		local old=folder:FindFirstChild('Junctions'); if old then retire(old) end
		junctionFolder.Parent=folder; folder:SetAttribute('JunctionVersion',2)
		if LaneDirections then folder:SetAttribute('LaneSerial',laneSerial) end
		if trafficSettings then for key,value in trafficSettings do folder:SetAttribute(key,value) end end
		return #planned,stats
	end
	function Network.edit(folder,road,points,config,reconnect)
		local links
		if reconnect then points,links=Network.attachEnds(folder,points,road) end
		return Network.apply(folder,road,points,config,links)
	end
	function Network.setLane(folder,junction,road,sign,lane,mask)
		assert(LaneDirections,'차로 편집 모듈이 없습니다.')
		return Network.apply(folder,nil,nil,nil,nil,nil,{Junction=junction,Road=road,Sign=sign,Lane=lane,Mask=mask})
	end
	return Network
end
