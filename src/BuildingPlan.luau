-- Floor-plan schema and geometry in building-local metres. No world mutation.
return function(codec)
	local B={Version=1,Grid=.25,StairWidth=3,StairDepth=4.8,LiftWidth=2.8,LiftDepth=2.8,DoorWidth=1.2,DoorHeight=2.15,DoorMargin=.12,
		WallMin=.08,WallMax=.4,WallDefault=.16}
	local function number(n,name)
		assert(type(n)=='number' and n==n and math.abs(n)<math.huge,'도면 숫자를 확인하세요: '..name);return n
	end
	function B.snap(n) return math.floor(n/B.Grid+.5)*B.Grid end
	function B.center(e) return if e.Kind=='Wall' then (e.X+e.X2)*.5 else e.X,if e.Kind=='Wall' then (e.Z+e.Z2)*.5 else e.Z end
	function B.angle(e) return if e.Kind=='Wall' then math.deg(math.atan2(-(e.Z2-e.Z),e.X2-e.X))%360 else e.Rotation end
	function B.wallLength(e) return math.sqrt((e.X2-e.X)^2+(e.Z2-e.Z)^2) end
	function B.wallProjection(e,x,z)
		local dx,dz=e.X2-e.X,e.Z2-e.Z
		local t=math.clamp(((x-e.X)*dx+(z-e.Z)*dz)/(dx*dx+dz*dz),0,1)
		return t,(x-e.X-t*dx)^2+(z-e.Z-t*dz)^2
	end
	function B.doorSpan(e)
		if e.DoorAt==nil then return nil end
		local d=e.DoorAt*B.wallLength(e)
		return d-B.DoorWidth*.5,d+B.DoorWidth*.5
	end
	function B.transform(e,dx,dz,angle)
		dx,dz,angle=number(dx,'이동 X'),number(dz,'이동 Z'),number(angle,'회전')
		local n=table.clone(e)
		if e.Kind=='Wall' then
			local x,z=B.center(e);local a=math.rad(angle);local c,s=math.cos(a),math.sin(a)
			local function rotate(px,pz) return x+c*(px-x)+s*(pz-z)+dx,z-s*(px-x)+c*(pz-z)+dz end
			n.X,n.Z=rotate(e.X,e.Z);n.X2,n.Z2=rotate(e.X2,e.Z2)
		else n.X,n.Z,n.Rotation=e.X+dx,e.Z+dz,(e.Rotation+angle)%360 end
		return n
	end
	function B.level(p,floor) return if floor==1 then 0 else p.GroundHeight+(floor-2)*p.FloorHeight end
	function B.height(p,floor) return if floor==1 then p.GroundHeight else p.FloorHeight end
	function B.bounds(e)
		if e.Kind=='Wall' then
			local t=e.Thickness*.5
			return {X0=math.min(e.X,e.X2)-t,X1=math.max(e.X,e.X2)+t,Z0=math.min(e.Z,e.Z2)-t,Z1=math.max(e.Z,e.Z2)+t}
		end
		local w=if e.Kind=='Stairs' then B.StairWidth elseif e.Kind=='Elevator' then B.LiftWidth else e.Width
		local d=if e.Kind=='Stairs' then B.StairDepth elseif e.Kind=='Elevator' then B.LiftDepth else e.Depth
		if e.Rotation%180~=0 then w,d=d,w end
		return {X0=e.X-w*.5,X1=e.X+w*.5,Z0=e.Z-d*.5,Z1=e.Z+d*.5}
	end
	local function intersects(a,b)
		return math.min(a.X1,b.X1)-math.max(a.X0,b.X0)>.001 and math.min(a.Z1,b.Z1)-math.max(a.Z0,b.Z0)>.001
	end
	function B.visible(e,floor) return e.Kind=='Elevator' or e.Floor==floor end
	-- Copy the selected floor's own objects, never its arrival ghosts or the
	-- shared elevator. The caller validates the entire candidate before saving.
	function B.copyFloors(plan,p,source,all)
		assert(p.Floors>1 and (all or source<p.Floors),'복사할 층이 없습니다.')
		local result={Version=1,Items={}};local template={};local ids={};local id=1
		local function destination(f) return f~=source and (all or f==source+1) end
		for _,e in plan.Items do
			ids[e.Id]=true
			if e.Kind~='Elevator' and e.Floor==source then table.insert(template,e) end
			if e.Kind=='Elevator' or not destination(e.Floor) then table.insert(result.Items,e)
			else assert(all,'다음 층의 기존 도면을 먼저 비워주세요.') end
		end
		assert(#template>0,'이 층에 복사할 벽·블록·계단이 없습니다.')
		local copied=0
		for f=1,p.Floors do if destination(f) then
			for _,e in template do if e.Kind~='Stairs' or f<p.Floors then
				while ids[id] do id+=1 end
				local item=table.clone(e);item.Id,item.Floor=id,f
				ids[id]=true;table.insert(result.Items,item);copied+=1
			end end
		end end
		assert(copied>0,'꼭대기 층에는 계단을 복사할 수 없습니다.')
		return result
	end
	function B.normalize(plan,p)
		assert(type(plan)=='table' and (plan.Version==nil or plan.Version==1),'지원하지 않는 도면입니다.')
		local result={Version=1,Items={}};local ids={};local items=plan.Items or {}
		assert(type(items)=='table' and #items<=256,'도면은 건물당 최대 256개 부품입니다.')
		for _,e in items do
			assert(type(e)=='table' and table.find({'Wall','Block','Stairs','Elevator'},e.Kind),'도면 부품 종류를 확인하세요.')
			local id=number(e.Id,'ID');assert(id%1==0 and id>0 and id<=1000000 and not ids[id],'도면 ID가 중복됐습니다.');ids[id]=true
			local f=if e.Kind=='Elevator' then 1 else number(e.Floor,'층')
			assert(f%1==0 and f>=1 and f<=p.Floors,'층수를 줄이기 전에 해당 층의 도면 부품을 지우세요.')
			assert(e.Kind~='Stairs' or f<p.Floors,'계단은 다음 층이 있는 층에 놓으세요.')
			assert(e.Kind~='Elevator' or p.Floors>=2,'엘리베이터는 2층 이상 건물에 놓으세요.')
			local n={Id=id,Kind=e.Kind,Floor=f,X=number(e.X,'X'),Z=number(e.Z,'Z')}
			if e.Kind=='Wall' then
				n.X2,n.Z2=number(e.X2,'끝 X'),number(e.Z2,'끝 Z');n.Thickness=number(e.Thickness or B.WallDefault,'벽 두께')
				assert(n.Thickness>=B.WallMin and n.Thickness<=B.WallMax,'벽 두께는 0.08~0.4m입니다.')
				assert((n.X2-n.X)^2+(n.Z2-n.Z)^2>=.24^2,'벽 길이는 0.25m 이상이어야 합니다.')
				if e.DoorAt~=nil then
					n.DoorAt=number(e.DoorAt,'문 위치')
					local a,b=B.doorSpan(n)
					assert(a>=B.DoorMargin-1e-6 and b<=B.wallLength(n)-B.DoorMargin+1e-6,'문을 넣을 벽 길이가 부족하거나 벽 끝에 너무 가깝습니다.')
				end
			else
				n.Rotation=number(e.Rotation or 0,'회전')%360;assert(n.Rotation%90==0,'회전은 90도 단위입니다.')
				if e.Kind=='Block' then
					n.Width,n.Depth=number(e.Width,'블록 폭'),number(e.Depth,'블록 깊이')
					assert(n.Width>=.25 and n.Depth>=.25,'블록은 0.25m 이상이어야 합니다.')
				end
			end
			local b=B.bounds(n)
			assert(b.X0>=-p.Width*.5+.28 and b.X1<=p.Width*.5-.28 and b.Z0>=-p.Depth*.5+.28 and b.Z1<=p.Depth*.5-.28,'외벽 안쪽에 배치하세요. 크기를 줄이기 전에 도면도 조절하세요.')
			table.insert(result.Items,n)
		end
		for i,a in result.Items do for j=i+1,#result.Items do
			local b=result.Items[j];local coreA=a.Kind=='Stairs' or a.Kind=='Elevator';local coreB=b.Kind=='Stairs' or b.Kind=='Elevator'
			if coreA or coreB then
				local same= a.Kind=='Elevator' or b.Kind=='Elevator' or a.Floor==b.Floor
				-- Stacked stairs are allowed; walls must not obstruct their upper exit.
				if not coreA and b.Kind=='Stairs' and a.Floor==b.Floor+1 then same=true end
				if not coreB and a.Kind=='Stairs' and b.Floor==a.Floor+1 then same=true end
				assert(not same or not intersects(B.bounds(a),B.bounds(b)),'벽·블록이 계단/엘리베이터 공간과 겹칩니다.')
			end
		end end
		return result
	end
	function B.decode(text,p)
		if text==nil or text=='' then return {Version=1,Items={}} end
		assert(type(text)=='string' and #text<=50000,'도면 저장 크기를 초과했습니다.')
		local ok,value=pcall(codec.Decode,text);assert(ok,'도면 JSON을 읽을 수 없습니다.')
		return B.normalize(value,p)
	end
	function B.encode(plan,p)
		local text=codec.Encode(B.normalize(plan,p));assert(#text<=50000,'도면 저장 크기를 초과했습니다.');return text
	end
	function B.holes(plan,floor)
		local holes={}
		for _,e in plan.Items do if (e.Kind=='Elevator' and floor>1) or (e.Kind=='Stairs' and e.Floor+1==floor) then table.insert(holes,B.bounds(e)) end end
		return holes
	end
	-- A rectangular tiling exactly subtracts every stair/lift opening. Merge
	-- adjacent X cells into strips to avoid one slab for every grid square.
	function B.tiles(width,depth,holes)
		local xs,zs={-width*.5,width*.5},{-depth*.5,depth*.5}
		for _,b in holes do table.insert(xs,b.X0);table.insert(xs,b.X1);table.insert(zs,b.Z0);table.insert(zs,b.Z1) end
		local function sorted(values)
			table.sort(values);local out={};for _,v in values do if #out==0 or math.abs(v-out[#out])>.00001 then table.insert(out,v) end end;return out
		end
		xs,zs=sorted(xs),sorted(zs);local result={}
		for z=1,#zs-1 do
			local start=nil
			for x=1,#xs do
				local clear=x<#xs
				if clear then local px,pz=(xs[x]+xs[x+1])*.5,(zs[z]+zs[z+1])*.5
					for _,b in holes do if px>b.X0 and px<b.X1 and pz>b.Z0 and pz<b.Z1 then clear=false;break end end
				end
				if clear and not start then start=xs[x] end
				if not clear and start then table.insert(result,{X0=start,X1=xs[x],Z0=zs[z],Z1=zs[z+1]});start=nil end
			end
		end
		return result
	end
	local function contains(e,x,z)
		local b=B.bounds(e);return x>=b.X0 and x<=b.X1 and z>=b.Z0 and z<=b.Z1
	end
	function B.pick(plan,floor,x,z,kind,wallTolerance)
		for i=#plan.Items,1,-1 do local e=plan.Items[i];if B.visible(e,floor) and (not kind or kind==e.Kind) then
			if e.Kind=='Wall' then
				local _,distance=B.wallProjection(e,x,z)
				if distance<math.max(wallTolerance or .18,e.Thickness*.5)^2 then return e end
			elseif contains(e,x,z) then return e end
		end end
		return nil
	end
	function B.pickArrival(plan,floor,x,z)
		for i=#plan.Items,1,-1 do
			local e=plan.Items[i]
			if e.Kind=='Stairs' and e.Floor+1==floor and contains(e,x,z) then return e end
		end
		return nil
	end
	return B
end
