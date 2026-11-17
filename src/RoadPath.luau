-- Persistent centerlines are shared by hand tracing and a future image importer.
return function(Vector3)
	local Path={StudsPerMeter=1/.28}
	Path.Defaults={Width=7,Lanes=2,Sidewalk=1.5,Curve=75,Lift=.05}
	Path.Limits={Width={2.5,24},Lanes={1,6},Sidewalk={0,5},Curve={0,100},Lift={0,2}}
	-- Odd totals allocate the extra lane toward the road's end control point.
	-- Incoming lanes are numbered from the center divider to the driver's right.
	function Path.lanes(config,sign)
		local total=config.Lanes
		local width=config.Width*Path.StudsPerMeter
		local laneWidth=width/total
		local split=math.floor(total/2)
		local divider=-width*.5+split*laneWidth
		local count=if total==1 then 1 elseif sign==1 then split else total-split
		local centers={}
		for i=1,count do centers[i]=if total==1 then 0 else sign*divider-(i-.5)*laneWidth end
		return {Count=count,Width=laneWidth,Centers=centers,Divider=if total==1 then 0 else divider,Split=split}
	end
	function Path.normalize(input)
		local out={}
		for key,default in Path.Defaults do
			local value=if input[key]==nil then default else input[key]
			local bounds=Path.Limits[key]
			assert(type(value)=='number' and value==value and value>=bounds[1] and value<=bounds[2],key..' 범위를 확인하세요.')
			if key=='Lanes' then assert(value%1==0,'차선 수는 정수여야 합니다.') end
			out[key]=value
		end
		assert(out.Width/out.Lanes>=1.8,'차선 하나의 폭을 1.8m 이상으로 설정하세요.')
		return out
	end
	function Path.validatePoints(points)
		assert(#points>=2 and #points<=128,'도로 점은 2~128개가 필요합니다.')
		for i,p in points do
			assert(typeof(p)=='Vector3' and p.X==p.X and p.Y==p.Y and p.Z==p.Z and p.Magnitude<1e6,'잘못된 도로 점입니다.')
			if i>1 then
				local d=p-points[i-1]
				assert(Vector3.new(d.X,0,d.Z).Magnitude>=1,'점 사이 간격을 1 stud 이상 띄우세요.')
			end
		end
	end
	function Path.sample(points,input)
		Path.validatePoints(points)
		local config=Path.normalize(input)
		local samples={}; local total=0
		for i=1,#points-1 do
			local a,b=points[i],points[i+1]
			local before,after=points[math.max(1,i-1)],points[math.min(#points,i+2)]
			local straight=b-a
			local smooth=config.Curve/100
			local t0=straight:Lerp((b-before)*.5,smooth)
			local t1=straight:Lerp((after-a)*.5,smooth)
			local count=math.max(1,math.ceil(straight.Magnitude/10))
			assert(#samples+count<=1024,'도로 한 개가 너무 깁니다. 나눠서 그리세요.')
			for j=if i==1 then 0 else 1,count do
				local t=j/count; local t2,t3=t*t,t*t*t
				local p=a*(2*t3-3*t2+1)+t0*(t3-2*t2+t)+b*(-2*t3+3*t2)+t1*(t3-t2)
				p=Vector3.new(p.X,math.clamp(p.Y,math.min(a.Y,b.Y),math.max(a.Y,b.Y)),p.Z)
				if #samples>0 then
					local delta=p-samples[#samples].P
					local horizontal=Vector3.new(delta.X,0,delta.Z).Magnitude
					assert(horizontal>.001,'도로가 되접힙니다. 점을 더 멀리 배치하세요.')
					assert(math.abs(delta.Y)/horizontal<=.25,'경사가 25%를 넘습니다. 높이를 낮추거나 점 간격을 늘리세요.')
					total+=delta.Magnitude
				end
				table.insert(samples,{P=p,Distance=total,Segment=i})
			end
		end
		for i,s in samples do
			local incoming=s.P-samples[math.max(1,i-1)].P
			local outgoing=samples[math.min(#samples,i+1)].P-s.P
			incoming=Vector3.new(incoming.X,0,incoming.Z)
			outgoing=Vector3.new(outgoing.X,0,outgoing.Z)
			if incoming.Magnitude<.001 then incoming=outgoing end
			if outgoing.Magnitude<.001 then outgoing=incoming end
			incoming,outgoing=incoming.Unit,outgoing.Unit
			assert(incoming:Dot(outgoing)>-.6,'너무 급한 코너입니다. 중간 점으로 완만하게 연결하세요.')
			local tangent=(incoming+outgoing).Unit
			s.Side=Vector3.new(-tangent.Z,0,tangent.X)
			s.Miter=math.min(2,1/math.max(.5,tangent:Dot(incoming)))
		end
		return {Samples=samples,Length=total,Config=config}
	end
	function Path.offset(sample,offset)
		return sample.P+sample.Side*(offset*sample.Miter)
	end
	function Path.at(data,distance)
		distance=math.clamp(distance,0,data.Length)
		for i=1,#data.Samples-1 do
			local a,b=data.Samples[i],data.Samples[i+1]
			if distance<=b.Distance+.00001 then
				local t=math.clamp((distance-a.Distance)/(b.Distance-a.Distance),0,1)
				return {P=a.P:Lerp(b.P,t),Side=a.Side:Lerp(b.Side,t).Unit,Miter=a.Miter+(b.Miter-a.Miter)*t,Distance=distance}
			end
		end
		return data.Samples[#data.Samples]
	end
	function Path.project(data,p)
		local best,at,position=math.huge,0,data.Samples[1].P
		for i=1,#data.Samples-1 do
			local a,b=data.Samples[i],data.Samples[i+1]
			local d=Vector3.new(b.P.X-a.P.X,0,b.P.Z-a.P.Z)
			local t=math.clamp(Vector3.new(p.X-a.P.X,0,p.Z-a.P.Z):Dot(d)/d:Dot(d),0,1)
			local q=a.P:Lerp(b.P,t)
			local distance=Vector3.new(p.X-q.X,0,p.Z-q.Z).Magnitude
			if distance<best then best,at,position=distance,a.Distance+(b.Distance-a.Distance)*t,q end
		end
		return position,at,best
	end
	-- Intersections of sampled centerlines. A grid avoids scanning every pair
	-- of short segments; arc-distance deduplication handles shared sample vertices.
	function Path.crossings(a,b)
		local function bounds(data)
			if data.Bounds then return data.Bounds end
			local box={math.huge,math.huge,-math.huge,-math.huge}
			for _,s in data.Samples do box[1]=math.min(box[1],s.P.X); box[2]=math.min(box[2],s.P.Z); box[3]=math.max(box[3],s.P.X); box[4]=math.max(box[4],s.P.Z) end
			data.Bounds=box; return box
		end
		local aa,bb=bounds(a),bounds(b)
		if aa[1]>bb[3] or aa[3]<bb[1] or aa[2]>bb[4] or aa[4]<bb[2] then return {} end
		local function cells(p,q,visit)
			for x=math.floor(math.min(p.X,q.X)/64),math.floor(math.max(p.X,q.X)/64) do
				for z=math.floor(math.min(p.Z,q.Z)/64),math.floor(math.max(p.Z,q.Z)/64) do visit(x..':'..z) end
			end
		end
		if not b.Grid then
			b.Grid={}
			for j=1,#b.Samples-1 do cells(b.Samples[j].P,b.Samples[j+1].P,function(key)
				if not b.Grid[key] then b.Grid[key]={} end; table.insert(b.Grid[key],j)
			end) end
		end
		local result={}
		local function cross(u,v) return u.X*v.Z-u.Z*v.X end
		for i=1,#a.Samples-1 do
			local p,q=a.Samples[i],a.Samples[i+1]; local u=q.P-p.P; local seen={}
			cells(p.P,q.P,function(key)
				for _,j in b.Grid[key] or {} do if not seen[j] then
					seen[j]=true
					local r,s=b.Samples[j],b.Samples[j+1]; local v=s.P-r.P
					local denominator=cross(u,v)
					if math.abs(denominator)>.00001 then
						local t,k=cross(r.P-p.P,v)/denominator,cross(r.P-p.P,u)/denominator
						if t>=-.00001 and t<=1.00001 and k>=-.00001 and k<=1.00001 then
							t,k=math.clamp(t,0,1),math.clamp(k,0,1)
							local da,db=p.Distance+(q.Distance-p.Distance)*t,r.Distance+(s.Distance-r.Distance)*k
							local pa,pb=p.P:Lerp(q.P,t),r.P:Lerp(s.P,k)
							local height=pa.Y-pb.Y+(a.Config.Lift-b.Config.Lift)*Path.StudsPerMeter
							if da>1 and da<a.Length-1 and db>1 and db<b.Length-1 and math.abs(height)<=.35 then
								local duplicate=false
								for _,hit in result do if math.abs(hit.A-da)<.05 and math.abs(hit.B-db)<.05 then duplicate=true; break end end
								if not duplicate then table.insert(result,{A=da,B=db,P=pa}) end
							end
						end
					end
				end end
			end)
		end
		return result
	end
	-- Split at exact cut boundaries so asphalt, curbs and lane lines meet portals.
	function Path.segments(data,cuts)
		local segments={}
		for i=1,#data.Samples-1 do
			local a,b=data.Samples[i],data.Samples[i+1]
			local cursor=a.Distance
			for _,cut in cuts or {} do
				if cut[2]>cursor and cut[1]<b.Distance then
					if cut[1]>cursor+.0001 then table.insert(segments,{Path.at(data,cursor),Path.at(data,cut[1])}) end
					cursor=math.max(cursor,cut[2])
				end
			end
			if cursor<b.Distance-.0001 then table.insert(segments,{Path.at(data,cursor),b}) end
		end
		return segments
	end
	function Path.closest(points,point)
		local best,index=math.huge,1
		for i=1,#points-1 do
			local a,b=points[i],points[i+1]
			local t=math.clamp((point-a):Dot(b-a)/(b-a):Dot(b-a),0,1)
			local distance=(point-a:Lerp(b,t)).Magnitude
			if distance<best then best,index=distance,i end
		end
		return index,best
	end
	return Path
end
