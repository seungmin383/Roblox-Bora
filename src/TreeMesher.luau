-- Sparse smooth-union signed distance field -> welded marching tetrahedra.
-- A single surface is extracted for trunk and limbs; no intersecting tube shells.
return function(Vector3)
	local Mesher = {}
	local cube = {{0,0,0},{1,0,0},{1,1,0},{0,1,0},{0,0,1},{1,0,1},{1,1,1},{0,1,1}}
	local tetrahedra = {{1,2,3,7},{1,3,4,7},{1,4,8,7},{1,8,5,7},{1,5,6,7},{1,6,2,7}}
	local function smoothMin(a,b,k)
		local h = math.max(k-math.abs(a-b),0)/k
		return math.min(a,b)-h*h*k*.25
	end
	function Mesher.build(skeleton, options)
		options = options or {}
		local step = options.Step or math.clamp(.22*math.sqrt(skeleton.Config.Thickness),.18,.25)
		local blend = .22*skeleton.Config.Thickness
		local minimum,maximum = Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
		for _, s in skeleton.Segments do
			local margin = math.max(s.R0,s.R1)+blend+step*2
			local extent = Vector3.new(margin,margin,margin)
			minimum = minimum:Min(s.A:Min(s.B)-extent)
			maximum = maximum:Max(s.A:Max(s.B)+extent)
		end
		minimum = Vector3.new(math.floor(minimum.X/step)*step-.037, -step*1.37, math.floor(minimum.Z/step)*step-.019)
		local nx,ny,nz = math.ceil((maximum.X-minimum.X)/step)+1,math.ceil((maximum.Y-minimum.Y)/step)+1,math.ceil((maximum.Z-minimum.Z)/step)+1
		local layer = nx*ny
		local function key(x,y,z) return x+y*nx+z*layer end
		local function position(x,y,z) return minimum+Vector3.new(x*step,y*step,z*step) end
		local values = {}
		local progress = options.Progress or function() end
		local paths,pathOrder={},{}
		for _,s in skeleton.Segments do
			if not paths[s.PathId] then paths[s.PathId]={}; table.insert(pathOrder,s.PathId) end
			table.insert(paths[s.PathId],s)
		end
		local prepared={}
		for _,pathId in pathOrder do
			local segments={}
			local lo,hi=Vector3.one*math.huge,Vector3.one*-math.huge
			for _,s in paths[pathId] do
				local padding=math.max(s.R0,s.R1,step*.8)+blend+step*2
				local ab=s.B-s.A
				table.insert(segments,{A=s.A,AB=ab,Length2=ab:Dot(ab),R0=s.R0,DR=s.R1-s.R0,
					Lo=s.A:Min(s.B)-Vector3.one*padding,Hi=s.A:Max(s.B)+Vector3.one*padding})
				lo=lo:Min(segments[#segments].Lo); hi=hi:Max(segments[#segments].Hi)
			end
			table.insert(prepared,{Segments=segments,Lo=lo,Hi=hi})
		end
		-- Only nearby segment groups participate in a surface query. This keeps
		-- the projection affordable when sliders generate many main branches.
		local spatial={}
		local function binKey(x,y,z) return x..':'..y..':'..z end
		for pi,path in prepared do
			for _,s in path.Segments do
				for z=math.floor(s.Lo.Z),math.floor(s.Hi.Z) do
					for y=math.floor(s.Lo.Y),math.floor(s.Hi.Y) do
						for x=math.floor(s.Lo.X),math.floor(s.Hi.X) do
							local id=binKey(x,y,z)
							local cell=spatial[id]
							if not cell then cell={}; spatial[id]=cell end
							if not cell[#cell] or cell[#cell].Id~=pi then table.insert(cell,{Id=pi,Segments={}}) end
							table.insert(cell[#cell].Segments,s)
						end
					end
				end
			end
		end
		-- Exact field and derivative, used to remove grid-sized scallops after
		-- extracting topology. Increasing resolution alone leaves thin tips wavy.
		local function surface(p)
			local distance,gradient=100,Vector3.zero
			for _,path in spatial[binKey(math.floor(p.X),math.floor(p.Y),math.floor(p.Z))] or {} do
				local best,normal=100,Vector3.zero
				for _,s in path.Segments do
					if p.X<s.Lo.X or p.Y<s.Lo.Y or p.Z<s.Lo.Z or p.X>s.Hi.X or p.Y>s.Hi.Y or p.Z>s.Hi.Z then continue end
					local raw=(p-s.A):Dot(s.AB)/s.Length2
					local t=math.clamp(raw,0,1)
					local offset=p-(s.A+s.AB*t)
					local magnitude=offset.Magnitude
					local radius=s.R0+s.DR*t
					local d=magnitude-math.max(radius,step*.8)
					if d<best then
						best=d; normal=if magnitude>1e-8 then offset/magnitude else Vector3.yAxis
						if raw>0 and raw<1 and radius>step*.8 then normal-=s.AB*(s.DR/s.Length2) end
					end
				end
				if best<100 then
					local weight=math.clamp(.5+(best-distance)/(2*blend),0,1)
					gradient=gradient*weight+normal*(1-weight)
					distance=smoothMin(distance,best,blend)
				end
			end
			if -p.Y>distance then return -p.Y,-Vector3.yAxis end
			return distance,gradient
		end
		for pi,pathId in pathOrder do
			local pathValues={}
			for _,s in paths[pathId] do
			local radius = math.max(s.R0,s.R1,step*.8)+blend+step*1.75
			local lo,hi = s.A:Min(s.B)-Vector3.one*radius,s.A:Max(s.B)+Vector3.one*radius
			local ab = s.B-s.A
			local length2 = ab:Dot(ab)
			for z=math.max(0,math.floor((lo.Z-minimum.Z)/step)),math.min(nz-1,math.ceil((hi.Z-minimum.Z)/step)) do
				for y=math.max(0,math.floor((lo.Y-minimum.Y)/step)),math.min(ny-1,math.ceil((hi.Y-minimum.Y)/step)) do
					for x=math.max(0,math.floor((lo.X-minimum.X)/step)),math.min(nx-1,math.ceil((hi.X-minimum.X)/step)) do
						local p = position(x,y,z)
						local t = math.clamp((p-s.A):Dot(ab)/length2,0,1)
						-- A minimum sampled radius prevents broken sub-voxel twigs.
						local d = (p-(s.A+ab*t)).Magnitude-math.max(s.R0+(s.R1-s.R0)*t,step*.8)
						if d < blend+step*1.75 then
							local id = key(x,y,z)
							-- Adjacent segments describe ONE limb. Smooth-unioning them
							-- individually adds a swelling at every sample joint.
							pathValues[id] = math.min(pathValues[id] or 100,d)
						end
					end
				end
			end
			end
			-- Blend only distinct limbs, where a rounded branch collar is wanted.
			for id,d in pathValues do values[id]=smoothMin(values[id] or 100,d,blend) end
			if pi%4==0 then progress(.4*pi/#pathOrder) end
		end
		-- Flat ground cut; caps are part of the same extracted closed surface.
		local cells = {}
		for id,d in values do
			local z=math.floor(id/layer); local y=math.floor((id-z*layer)/nx); local x=id%nx
			d = math.max(d,-position(x,y,z).Y)
			values[id] = d
			if d < 0 then
				for dz=-1,0 do for dy=-1,0 do for dx=-1,0 do
					if x+dx>=0 and x+dx<nx-1 and y+dy>=0 and y+dy<ny-1 and z+dz>=0 and z+dz<nz-1 then
						cells[key(x+dx,y+dy,z+dz)] = true
					end
				end end end
			end
		end
		local vertices,faces,edgeCache = {},{},{}
		local function crossing(a,b)
			local ka,kb=a.Id,b.Id
			local edge=if ka<kb then ka..":"..kb else kb..":"..ka
			local index=edgeCache[edge]
			if not index then
				table.insert(vertices,a.P:Lerp(b.P,a.D/(a.D-b.D)))
				index=#vertices; edgeCache[edge]=index
			end
			return index
		end
		local function triangle(a,b,c,outward)
			local cross=(vertices[b]-vertices[a]):Cross(vertices[c]-vertices[a])
			if cross.Magnitude==0 then return end
			if cross:Dot(outward)<0 then b,c=c,b end
			table.insert(faces,{a,b,c})
		end
		local cellIds={}; for id in cells do table.insert(cellIds,id) end; table.sort(cellIds)
		for ci,id in cellIds do
			local z=math.floor(id/layer); local y=math.floor((id-z*layer)/nx); local x=id%nx
			local corners={}
			for i,c in cube do
				local node=key(x+c[1],y+c[2],z+c[3])
				corners[i]={Id=node,D=values[node] or step*3,P=position(x+c[1],y+c[2],z+c[3])}
			end
			for _,tet in tetrahedra do
				local inside,outside={},{}
				for _,i in tet do table.insert(if corners[i].D<0 then inside else outside,corners[i]) end
				if #inside==1 then
					local a=inside[1]
					triangle(crossing(a,outside[1]),crossing(a,outside[2]),crossing(a,outside[3]),outside[1].P-a.P)
				elseif #inside==3 then
					local a=outside[1]
					triangle(crossing(a,inside[1]),crossing(a,inside[2]),crossing(a,inside[3]),a.P-inside[1].P)
				elseif #inside==2 then
					local a,b,c,d=inside[1],inside[2],outside[1],outside[2]
					local ac,ad,bc,bd=crossing(a,c),crossing(a,d),crossing(b,c),crossing(b,d)
					local outward=(c.P+d.P-a.P-b.P)*.5
					triangle(ac,ad,bd,outward); triangle(ac,bd,bc,outward)
				end
			end
			if ci%1200==0 then progress(.4+.4*ci/#cellIds) end
		end
		-- Discard sub-voxel tip specks, never a large disconnected limb.
		local adjacency={}
		for i=1,#vertices do adjacency[i]={} end
		for _,f in faces do
			for j=1,3 do local a,b=f[j],f[j%3+1]; adjacency[a][b]=true; adjacency[b][a]=true end
		end
		local seen,components={},{}
		for i=1,#vertices do
			if not seen[i] then
				local component={}; local stack={i}; seen[i]=true
				while #stack>0 do
					local v=table.remove(stack); table.insert(component,v)
					for other in adjacency[v] do if not seen[other] then seen[other]=true; table.insert(stack,other) end end
				end
				table.insert(components,component)
			end
		end
		table.sort(components,function(a,b) return #a>#b end)
		if options.Debug then local sizes={}; for _,c in components do table.insert(sizes,#c) end; print('islands',table.concat(sizes,',')) end
		assert(#components>0,"Empty wood surface")
		local discarded=0; for i=2,#components do discarded+=#components[i] end
		assert((not components[2] or #components[2] < #components[1]*.025) and discarded < #components[1]*.15,
			"A branch disconnected from the trunk; reduce spread or thickness")
		local keep={}; for _,v in components[1] do keep[v]=true end
		local keptFaces={}; for _,f in faces do if keep[f[1]] then table.insert(keptFaces,f) end end
		faces=keptFaces
		-- Restrained Taubin smoothing rounds collars without collapsing their volume.
		for _,factor in {.32,-.30,.32,-.30} do
			local nextVertices={}
			for i,p in vertices do
				local sum,count=Vector3.zero,0
				for other in adjacency[i] do sum+=vertices[other]; count+=1 end
				nextVertices[i]=if count>0 and p.Y>.025 then p+(sum/count-p)*factor else p
			end
			vertices=nextVertices
		end
		for i,p in vertices do
			if keep[i] and p.Y>.025 then
				for _=1,3 do
					local d,g=surface(p)
					local length2=g:Dot(g)
					if length2>1e-8 then p-=g*(d/length2) end
				end
				vertices[i]=p
			end
			if i%2000==0 then progress(.8+.18*i/#vertices) end
		end
		-- Refine only edges whose straight chord visibly cuts into the analytic
		-- surface. Thin limbs need more vertices around their circumference, not
		-- a globally dense voxel grid. Shared edge points keep the mesh watertight.
		local midpoints={}
		for _,f in faces do
			for j=1,3 do
				local a,b=f[j],f[j%3+1]
				local id=if a<b then a..':'..b else b..':'..a
				if midpoints[id]==nil then
					local p=(vertices[a]+vertices[b])*.5
					local d,g=surface(p)
					if d<-.008 and p.Y>.025 and g:Dot(g)>1e-8 then
						for _=1,3 do
							local length2=g:Dot(g)
							if length2>1e-8 then p-=g*(d/length2) end
							d,g=surface(p)
						end
						table.insert(vertices,p); keep[#vertices]=true; midpoints[id]=#vertices
					else midpoints[id]=false end
				end
			end
		end
		local refined={}
		local function add(a,b,c) table.insert(refined,{a,b,c}) end
		for _,f in faces do
			local mids,count={},0
			for j=1,3 do
				local a,b=f[j],f[j%3+1]
				mids[j]=midpoints[if a<b then a..':'..b else b..':'..a]
				if mids[j] then count+=1 end
			end
			local a,b,c=f[1],f[2],f[3]
			if count==0 then table.insert(refined,f)
			elseif count==3 then
				add(a,mids[1],mids[3]); add(mids[1],b,mids[2]); add(mids[3],mids[2],c); add(mids[1],mids[2],mids[3])
			elseif count==1 then
				for j=1,3 do if mids[j] then
					add(f[j],mids[j],f[(j+1)%3+1]); add(mids[j],f[j%3+1],f[(j+1)%3+1])
				end end
			else
				for j=1,3 do if mids[j] and mids[j%3+1] then
					local x,y,z=f[j],f[j%3+1],f[(j+1)%3+1]
					local m,n=mids[j],mids[j%3+1]
					add(y,n,m); add(m,n,z); add(x,m,z)
				end end
			end
		end
		faces=refined
		local remap,compact={},{}
		for i,p in vertices do if keep[i] then remap[i]=#compact+1; table.insert(compact,p) end end
		vertices=compact
		local normals={}; for i=1,#vertices do normals[i]=Vector3.zero end
		for _,f in faces do
			for j=1,3 do f[j]=remap[f[j]] end
			local n=(vertices[f[2]]-vertices[f[1]]):Cross(vertices[f[3]]-vertices[f[1]])
			for _,v in f do normals[v]+=n end
		end
		minimum,maximum=Vector3.one*math.huge,Vector3.one*-math.huge
		for i,p in vertices do
			minimum=minimum:Min(p); maximum=maximum:Max(p)
			local _,gradient=surface(p)
			normals[i]=if gradient.Magnitude>1e-8 then gradient.Unit else normals[i].Unit
		end
		local center=(minimum+maximum)*.5
		local uvs={}
		for i,p in vertices do
			-- Repeating restrained bark uses world vertical grain; no reused atlas islands.
			uvs[i]={ (p.X*.41+p.Z*.29),p.Y*.32 }
			vertices[i]=p-center
		end
		progress(1)
		return { Vertices=vertices, Faces=faces, Normals=normals, UVs=uvs,
			Center=center, Bounds=maximum-minimum, Step=step, Components=1, DiscardedVertices=discarded }
	end
	return Mesher
end

