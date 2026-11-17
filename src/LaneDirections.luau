-- Direction masks: straight=1, left=2, right=4. Persisted on each junction,
-- keyed by the actual road reference and outward arc sign, never screen order.
return function(api,Path)
	local V,Instance=api.Vector3,api.Instance
	local L={Straight=1,Left=2,Right=4}
	function L.label(mask)
		local names={};for _,item in {{2,'좌회전'},{1,'직진'},{4,'우회전'}} do if bit32.band(mask,item[1])~=0 then table.insert(names,item[2]) end end
		return table.concat(names,'·')
	end
	local function signature(roads)
		local ids={};for road in roads do table.insert(ids,tostring(road:GetAttribute('ObjectId'))) end;table.sort(ids)
		return table.concat(ids,'|'),ids[1]
	end
	local function oldInfo(model)
		local roads,anchors={},{}
		local members=model:FindFirstChild('Members')
		if members then for _,ref in members:GetChildren() do if ref:IsA('ObjectValue') and ref.Value then
			roads[ref.Value]=true;anchors[ref.Value]=ref:GetAttribute('At') or (if ref:GetAttribute('Endpoint')=='End' then 1 else 0)
		end end end
		local key,canonical=signature(roads)
		local distance=0;for road,at in anchors do if tostring(road:GetAttribute('ObjectId'))==canonical then distance=at end end
		return {Model=model,Roads=roads,Anchors=anchors,Signature=key,Distance=distance,Center=model:GetAttribute('Center')}
	end
	function L.available(plan,arm)
		local incoming=-arm.Direction;local mask=0
		for _,other in plan.Arms do if other~=arm then
			local dot=incoming:Dot(other.Direction)
			local cross=incoming.X*other.Direction.Z-incoming.Z*other.Direction.X
			local bit=if dot>.72 then 1 elseif cross<0 then 2 else 4
			mask=bit32.bor(mask,bit)
		end end
		return mask
	end
	local function defaultMask(available,lane,count)
		if bit32.band(available,1)~=0 then return 1 end
		if count>1 then
			local bit=if lane==1 then 2 else 4
			if bit32.band(available,bit)~=0 then return bit end
		end
		return available
	end
	-- Pair equal-topology junctions by their longitudinal order. If a new
	-- junction is inserted, only unchanged anchors are reused. T <-> X merges
	-- also reuse the unique nearby junction sharing the original road pair.
	function L.bind(plans,previous,serial,input)
		local old,oldGroups,newGroups={},{},{}
		if previous then for _,model in previous:GetChildren() do
			serial=math.max(serial,tonumber(model:GetAttribute('LaneKey')) or 0)
			local info=oldInfo(model);table.insert(old,info)
			oldGroups[info.Signature]=oldGroups[info.Signature] or {};table.insert(oldGroups[info.Signature],info)
		end end
		for _,plan in plans do
			plan.Roads,plan.Anchors={},{}
			for _,a in plan.Approaches do
				local road=a.State.Road;plan.Roads[road]=true
				plan.Anchors[road]=a.At or (if a.End=='End' then 1 else 0)
			end
			local key,canonical=signature(plan.Roads);plan.Signature=key
			for road,at in plan.Anchors do if tostring(road:GetAttribute('ObjectId'))==canonical then plan.Distance=at end end
			newGroups[key]=newGroups[key] or {};table.insert(newGroups[key],plan)
		end
		for key,list in newGroups do
			local candidates=oldGroups[key] or {}
			table.sort(list,function(a,b) return a.Distance<b.Distance end)
			table.sort(candidates,function(a,b) return a.Distance<b.Distance end)
			if #list==#candidates then for i,plan in list do plan.Previous=candidates[i];candidates[i].Used=true end
			else
				for _,plan in list do
					local closest,delta=nil,.0001
					for _,candidate in candidates do
						local d=math.abs(plan.Distance-candidate.Distance)
						if not candidate.Used and d<delta then closest,delta=candidate,d end
					end
					if closest then plan.Previous=closest;closest.Used=true end
				end
			end
		end
		for _,plan in plans do if not plan.Previous then
			local candidates={}
			for _,candidate in old do if not candidate.Used then
				local common=0;for road in plan.Roads do if candidate.Roads[road] then common+=1 end end
				if common>=2 and candidate.Center and (candidate.Center-plan.Center).Magnitude<8 then table.insert(candidates,candidate) end
			end end
			if #candidates==1 then plan.Previous=candidates[1];candidates[1].Used=true end
		end end
		local applied=false
		for _,plan in plans do
			local oldModel=plan.Previous and plan.Previous.Model
			plan.LaneKey=oldModel and oldModel:GetAttribute('LaneKey')
			if not plan.LaneKey then serial+=1;plan.LaneKey=tostring(serial) end
			plan.LaneRules={}
			for index,arm in plan.Arms do
				local road=plan.Approaches[arm.Approach].State.Road
				local layout=Path.lanes(arm.Data.Config,arm.Sign)
				local available=L.available(plan,arm)
				local rule={Road=road,Sign=arm.Sign,Count=layout.Count,Available=available,Masks={},At=arm.Anchor/arm.Data.Length,Arm=index,Position=(arm.Left+arm.Right)*.5,ArrowVisible=false}
				local saved=oldModel and oldModel:FindFirstChild('LaneDirections')
				local prior
				if saved then
					assert(saved:GetAttribute('AssetKind')=='BoraLaneDirections','LaneDirections 이름의 사용자 폴더가 있습니다.')
					for _,ref in saved:GetChildren() do if ref:IsA('ObjectValue') and ref.Value==road and ref:GetAttribute('Sign')==arm.Sign then prior=ref;break end end
				end
				for lane=1,layout.Count do
					local mask=prior and prior:GetAttribute('Lane'..lane)
					mask=if type(mask)=='number' then bit32.band(mask,available) else 0
					rule.Masks[lane]=if mask>0 then mask else defaultMask(available,lane,layout.Count)
				end
				if input and oldModel==input.Junction and road==input.Road and arm.Sign==input.Sign then
					assert(type(input.Lane)=='number' and input.Lane%1==0 and input.Lane>=1 and input.Lane<=layout.Count,'차로를 다시 선택하세요.')
					assert(type(input.Mask)=='number' and input.Mask%1==0 and input.Mask>=1 and input.Mask<=7,'진행 방향을 하나 이상 선택하세요.')
					assert(bit32.band(input.Mask,available)==input.Mask,'그 방향으로 연결되는 도로가 없습니다.')
					rule.Masks[input.Lane]=input.Mask;applied=true
				end
				table.insert(plan.LaneRules,rule)
			end
		end
		assert(not input or applied,'편집 대상 교차로가 바뀌었습니다. 진입로를 다시 선택하세요.')
		return serial
	end
	function L.decorate(plan,settings,result,section)
		local scale=Path.StudsPerMeter
		local depth=if settings.Crosswalks then settings.CrosswalkWidth else 0
		local base=settings.CrosswalkOffset+depth+(if settings.StopLines then settings.StopGap+.4 else 0)+1
		local length=2.8;local finish=(base+length)*scale
		for index,arm in plan.Arms do
			local rule=plan.LaneRules[index];local layout=Path.lanes(arm.Data.Config,arm.Sign)
			local room=if arm.Sign==1 then arm.Data.Length-arm.Anchor-arm.Trim else arm.Anchor-arm.Trim
			room=math.min(room,arm.TrafficRoom or math.huge)
			if room>finish+1 then
				rule.ArrowVisible=true;rule.Position=section(arm,(base+length*.5)*scale)
				for lane=1,layout.Count do
					local mask=rule.Masks[lane];local width=layout.Width/scale*.55;local stem=.14
					local function emit(points)
						local corners={}
						for _,p in points do
							local center,u=section(arm,(base+length*.5-p[2])*scale)
							table.insert(corners,center+u*(layout.Centers[lane]-p[1]*scale))
						end
						table.insert(result.Markings,{Kind='LaneArrow',Corners=corners,Arm=index,Lane=lane,Mask=mask})
					end
					local straight=bit32.band(mask,1)~=0
					local top=if straight then .65 else .2+stem*.5
					emit({{-stem*.5,-1.4},{stem*.5,-1.4},{stem*.5,top},{-stem*.5,top}})
					if straight then emit({{-width*.24,.65},{width*.24,.65},{0,1.4}}) end
					for _,turn in {{2,-1},{4,1}} do if bit32.band(mask,turn[1])~=0 then
						local sign=turn[2]
						emit({{sign*stem*.5,.2-stem*.5},{sign*width*.34,.2-stem*.5},{sign*width*.34,.2+stem*.5},{sign*stem*.5,.2+stem*.5}})
						emit({{sign*width*.34,-.13},{sign*width*.34,.53},{sign*width*.5,.2}})
					end end
				end
				local a,b=arm.Anchor+arm.Sign*arm.Trim,arm.Anchor+arm.Sign*(arm.Trim+finish+.15*scale)
				table.insert(result.Cuts,{Approach=arm.Approach,Range={math.min(a,b),math.max(a,b)}})
			else result.LimitedArrows=(result.LimitedArrows or 0)+1 end
		end
	end
	function L.write(model,plan)
		model:SetAttribute('LaneKey',plan.LaneKey)
		local folder=Instance.new('Folder');folder.Name='LaneDirections';folder:SetAttribute('AssetKind','BoraLaneDirections');folder.Parent=model
		for _,rule in plan.LaneRules do
			local ref=Instance.new('ObjectValue');ref.Name,ref.Value='Approach'..rule.Arm,rule.Road
			for key,value in {Sign=rule.Sign,Count=rule.Count,Available=rule.Available,At=rule.At,Arm=rule.Arm,Position=rule.Position,ArrowVisible=rule.ArrowVisible} do ref:SetAttribute(key,value) end
			for lane,mask in rule.Masks do ref:SetAttribute('Lane'..lane,mask) end
			ref.Parent=folder
		end
	end
	function L.entries(folder,road)
		local list={};local junctions=folder and folder:FindFirstChild('Junctions')
		if junctions then for _,model in junctions:GetChildren() do
			local rules=model:FindFirstChild('LaneDirections')
			if rules and rules:GetAttribute('AssetKind')=='BoraLaneDirections' then for _,ref in rules:GetChildren() do
				if ref:IsA('ObjectValue') and ref.Value and (not road or ref.Value==road) then
					local item={Junction=model,Key=model:GetAttribute('LaneKey'),Road=ref.Value,Masks={}}
					for _,key in {'Sign','Count','Available','At','Arm','Position','ArrowVisible'} do item[key]=ref:GetAttribute(key) end
					for i=1,item.Count do item.Masks[i]=ref:GetAttribute('Lane'..i) end
					table.insert(list,item)
				end
			end end
		end end
		table.sort(list,function(a,b) if a.At==b.At then return a.Sign<b.Sign end;return a.At<b.At end)
		return list
	end
	return L
end
