-- Geometry planning only. Persistent host references are managed by RoadNetwork.
return function(Vector3,Path)
	local J={}
	local function flat(v) return Vector3.new(v.X,0,v.Z) end
	local function cross(a,b) return a.X*b.Z-a.Z*b.X end
	local function side(d) return Vector3.new(-d.Z,0,d.X) end
	local function tangent(s) return Vector3.new(s.Side.Z,0,-s.Side.X) end
	local function intersect(a,u,b,v)
		local denominator=cross(u,v)
		if math.abs(denominator)<.00001 then return nil end
		local t=cross(b-a,v)/denominator
		local k=cross(b-a,u)/denominator
		return a+u*t,t,k
	end
	local function bezier(a,b,c,t) return a*(1-t)^2+b*(2*t*(1-t))+c*t*t end
	-- Each through road supplies two arms; an attached endpoint supplies one.
	function J.planApproaches(approaches)
		local first=approaches[1]
		local hub=Path.at(first.Data,first.At*first.Data.Length)
		local center=hub.P+Vector3.yAxis*(first.Data.Config.Lift*Path.StudsPerMeter)
		local arms,cuts={},{}
		local radius=math.huge
		for index,approach in approaches do
			assert(approach.End==nil or approach.End=='Start' or approach.End=='End','Invalid junction endpoint')
			local data=approach.Data
			local distance=if approach.End=='Start' then 0 elseif approach.End=='End' then data.Length else approach.At*data.Length
			local p=Path.at(data,distance)
			local half=data.Config.Width*Path.StudsPerMeter*.5
			radius=math.min(radius,half*.5)
			cuts[index]={distance,distance}
			for _,sign in (if approach.End=='Start' then {1} elseif approach.End=='End' then {-1} else {1,-1}) do
				table.insert(arms,{Direction=tangent(p)*sign,Half=half,Walk=data.Config.Sidewalk*Path.StudsPerMeter,Data=data,Sign=sign,Anchor=distance,Approach=index})
			end
		end
		assert(#arms==3 or #arms==4,'교차로에는 세 방향 또는 네 방향만 연결할 수 있습니다.')
		for _,arm in arms do arm.Angle=math.atan2(arm.Direction.Z,arm.Direction.X); arm.Trim=radius+2 end
		table.sort(arms,function(a,b) return a.Angle<b.Angle end)
		for i,a in arms do
			local b=arms[i%#arms+1]
			local gap=(b.Angle-a.Angle)%(math.pi*2)
			assert(gap>=math.acos(.72) and gap<=math.pi+.01,'교차로 진입 각도는 약 45~135도로 만드세요.')
			a.Back=gap>math.pi-.01
			if not a.Back then
				local _,u,v=intersect(center+side(a.Direction)*a.Half,a.Direction,center-side(b.Direction)*b.Half,b.Direction)
				assert(u and u>=0 and v>=0,'교차로 모서리를 구성할 수 없습니다. 폭 또는 진입 각도를 조절하세요.')
				a.Trim=math.max(a.Trim,u+radius+2); b.Trim=math.max(b.Trim,v+radius+2)
			end
		end
		for _,arm in arms do
			local endDistance=arm.Anchor+arm.Sign*arm.Trim
			assert(endDistance>1 and endDistance<arm.Data.Length-1,'교차로가 도로 끝에 너무 가깝습니다. 도로를 더 길게 그리세요.')
			local s=Path.at(arm.Data,endDistance)
			local p=s.P+Vector3.yAxis*(arm.Data.Config.Lift*Path.StudsPerMeter)
			local left=s.Side*(arm.Sign*s.Miter)
			arm.Left,arm.Right=p+left*arm.Half,p-left*arm.Half
			arm.OuterLeft,arm.OuterRight=p+left*(arm.Half+arm.Walk),p-left*(arm.Half+arm.Walk)
			arm.PortalDirection=tangent(s)*arm.Sign
			local cut=cuts[arm.Approach]
			cut[1],cut[2]=math.min(cut[1],endDistance),math.max(cut[2],endDistance)
		end
		local perimeter,bands={},{}
		for i,a in arms do
			local b=arms[i%#arms+1]
			table.insert(perimeter,a.Right); table.insert(perimeter,a.Left)
			local control,outerControl
			if not a.Back then
				control=intersect(a.Left,a.PortalDirection,b.Right,b.PortalDirection)
				outerControl=intersect(a.OuterLeft,a.PortalDirection,b.OuterRight,b.PortalDirection)
				assert(control and outerControl and flat(control-center).Magnitude<math.max(a.Trim,b.Trim)*3,'교차로 근처의 곡선을 더 완만하게 만드세요.')
				control=Vector3.new(control.X,(a.Left.Y+b.Right.Y)*.5,control.Z)
				outerControl=Vector3.new(outerControl.X,(a.OuterLeft.Y+b.OuterRight.Y)*.5,outerControl.Z)
			end
			local count=if a.Back then 1 else 10
			local lastInner,lastOuter=a.Left,a.OuterLeft
			for k=1,count do
				local t=k/count
				local inner=if a.Back then a.Left:Lerp(b.Right,t) else bezier(a.Left,control,b.Right,t)
				local outer=if a.Back then a.OuterLeft:Lerp(b.OuterRight,t) else bezier(a.OuterLeft,outerControl,b.OuterRight,t)
				if k<count then table.insert(perimeter,inner) end
				if a.Walk>0 or b.Walk>0 then table.insert(bands,{lastInner,lastOuter,outer,inner}) end
				lastInner,lastOuter=inner,outer
			end
		end
		for i,p in perimeter do
			assert(cross(flat(p-center),flat(perimeter[i%#perimeter+1]-center))>=-.001,'교차로 코너가 겹칩니다. 진입부를 곧게 펴세요.')
		end
		return {Center=center,Perimeter=perimeter,Bands=bands,Cuts=cuts,Arms=arms,Approaches=approaches}
	end
	function J.plan(host,branch,at,endpoint)
		local plan=J.planApproaches({{Data=host,At=at},{Data=branch,End=endpoint}})
		plan.HostCut,plan.BranchCut=plan.Cuts[1],plan.Cuts[2]
		return plan
	end
	function J.checkCuts(cuts)
		table.sort(cuts,function(a,b) return a[1]<b[1] end)
		for i=2,#cuts do assert(cuts[i][1]>=cuts[i-1][2]+1,'교차로가 너무 가깝습니다. 연결점을 더 멀리 띄우세요.') end
	end
	return J
end
