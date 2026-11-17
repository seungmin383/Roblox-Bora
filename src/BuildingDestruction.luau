-- Runtime-only structural bookkeeping. A building keeps its saved recipe.
return function(api,effects)
	local I,V,C,E=api.Instance,api.Vector3,api.CFrame,api.Enum
	local D={BlastRadius=11,SupportLimit=.48};local states=setmetatable({},{__mode='k'})
	local looseWalls=setmetatable({},{__mode='k'})
	local function prop(part,k,default) local value=part:GetAttribute(k);return if type(value)=='number' and value>0 then value else default end
	local function isWall(n)
		return n=='GroundRearWall' or n=='GroundSideWall' or n=='MasonryPier' or n=='CornerPier' or n:match('^UpperWall')~=nil or n=='UpperMasonry'
			or n:match('^PlanWall_')~=nil or n=='WallStart' or n=='WallEnd' or n:match('^PlanBlock_')~=nil
	end
	local function isSupport(n)
		return n=='GroundRearWall' or n=='GroundSideWall' or n=='MasonryPier' or n=='CornerPier' or n=='UpperMasonry' or n:match('^UpperWall')~=nil
	end
	local function attachmentRole(n)
		if n=='RoofCap' or n=='RoofSlab' then return 'roofDeck' end
		if n=='GroundCeiling' then return 'ceiling' end
		if n:match('^FloorBand') then return 'band' end
		if n:match('^RoofParapet') or n=='Parapet' or n=='RoofAccess' or n=='RoofDoor' or n=='AccessCap' or n:match('^Coping')
			or n=='AirConditioner' or n:match('^Condenser') then return 'roof' end
		if n=='WindowGlass' or n=='WindowRecess' or n=='WindowMullion' or n=='WindowFrame'
			or n=='WindowSill' or n=='WindowRail' or n=='OpeningReveal' then return 'window' end
		if n:match('^Storefront') or n=='SideStorefrontGlass' or n=='SideMullion' or n=='SideWindowRail'
			or n=='ShopSign' or n=='CanvasAwning' or n=='AwningValance' or n=='CanvasPanel' or n=='Valance' then return 'front' end
		if n=='BalconyRail' or n=='BalconyBaluster' or n:match('^Balcony.*Rail') or n=='BalconyPicket' then return 'balcony' end
		return nil
	end
	local function canBlast(part)
		local n=part.Name
		return isWall(n) or n:match('^WallRemainder')~=nil or n:match('^Window')~=nil or n:match('^Opening')~=nil
			or n:match('^Storefront')~=nil or n:match('^Door')~=nil or n:match('^FloorSlab')~=nil or n:match('^Balcony')~=nil
			or n=='SideStorefrontGlass' or n=='SideFascia' or n=='SideSill' or n=='OpenEntryDoor' or n=='ServiceDoor'
			or n=='GroundCeiling' or n=='RoofCap' or n=='RoofSlab'
	end
	local function namedWall(part)
		return part:GetAttribute('BoraBreakableWall')==true or part.Name:lower():find('wall',1,true)~=nil
			or part.Name:find('벽',1,true)~=nil
	end
	local function wallPart(part)
		return part:IsA('Part') and part.Shape==E.PartType.Block and part.Anchored and part.CanCollide and part.Transparency<1
	end
	local function uprightWall(part)
		local s=part.Size
		return wallPart(part) and part.CFrame.UpVector.Y>.96 and s.Y>=4 and math.max(s.X,s.Z)>=3.2
			and math.min(s.X,s.Z)<=2.2
	end
	local function partition(part,geometry)
		local at=part
		while at and at~=geometry do
			local root=at.Parent
			if root and root.Name=='FloorPlanInterior' and type(at:GetAttribute('PlanId'))=='number' then
				-- Straight walls and blocks are Parts. A wall with a door is a
				-- Model with separately collidable sections around the opening.
				return at:IsA('Part') or at.Name:match('^PlanWall_')~=nil
					or at:FindFirstChild('DoorHeader')~=nil
			end
			at=root
		end
		return false
	end
	local function appearance(to,from)
		to.Color,to.Material,to.MaterialVariant=from.Color,from.Material,from.MaterialVariant
		to.Transparency,to.Reflectance,to.CollisionGroup=from.Transparency,from.Reflectance,from.CollisionGroup
		to.TopSurface,to.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth
	end
	local function make(source,cf,size,wedge,name)
		local p=I.new(if wedge then 'WedgePart' else 'Part')
		p.Name,p.CFrame,p.Size=name,cf,size;p.Anchored=true
		appearance(p,source);p.CanCollide,p.CanQuery,p.CanTouch=source.CanCollide,true,false
		return p
	end
	function D.distance(cf,size,point)
		local q=cf:PointToObjectSpace(point);local h=size*.5
		return V.new(math.max(0,math.abs(q.X)-h.X),math.max(0,math.abs(q.Y)-h.Y),math.max(0,math.abs(q.Z)-h.Z)).Magnitude
	end
	local function box(s,cf,size)
		local rel=s.Base:ToObjectSpace(cf);local u,v,w=rel.RightVector,rel.UpVector,rel.LookVector
		local half=V.new(
			math.abs(u.X)*size.X+math.abs(v.X)*size.Y+math.abs(w.X)*size.Z,
			math.abs(u.Y)*size.X+math.abs(v.Y)*size.Y+math.abs(w.Y)*size.Z,
			math.abs(u.Z)*size.X+math.abs(v.Z)*size.Y+math.abs(w.Z)*size.Z)*.5
		return {Min=rel.Position-half,Max=rel.Position+half,Center=rel.Position,NormalX=half.X<half.Z}
	end
	local function gap(a,b,k)
		return math.max(0,a.Min[k]-b.Max[k],b.Min[k]-a.Max[k])
	end
	local function overlap(a,b,k)
		return math.min(a.Max[k],b.Max[k])-math.max(a.Min[k],b.Min[k])
	end
	local function initAttachments(s)
		local hosts,decks,roof,balconies,panes={},{},{},{},{}
		local attachments={}
		for _,cell in s.Cells do
			local r=cell.Record;local n=r.Name
			if r.Role then table.insert(attachments,cell) end
			if not r.Partition and (isWall(n) or n=='WindowApron' or n=='WindowLintel' or n=='DoorJamb' or n=='SideSill' or n=='SideFascia' or n=='GroundCeiling') then table.insert(hosts,cell) end
			if n=='GroundCeiling' or n=='GroundFloorSlab' or n:match('^FloorSlab') then table.insert(decks,cell) end
			if r.Role=='roofDeck' then table.insert(roof,cell) end
			if n=='BalconySlab' then table.insert(balconies,cell) end
			if n=='WindowGlass' then table.insert(panes,cell) end
		end
		local openingLinks={}
		local function put(links,host,weight) links[host]=(links[host] or 0)+weight end
		for _,cell in attachments do
			local a=cell.Box;local role=cell.Record.Role
			local links={}
			local structuralDeck=role=='roofDeck' or role=='ceiling'
			if role=='roof' or role=='balcony' or role=='band' or structuralDeck then
				local candidates=if role=='roof' then roof elseif role=='balcony' then balconies elseif role=='band' then decks else hosts
				for _,host in candidates do
					local b=host.Box
					local near=if role=='roof' then gap(a,b,'Y')<=9 elseif role=='balcony' then gap(a,b,'Y')<=2 else gap(a,b,'Y')<=.9
					-- A deck rests on support below it; a neighboring wall
					-- above the deck is not one of its anchors.
					if near and (not structuralDeck or b.Center.Y<a.Center.Y) then
						local x,z=overlap(a,b,'X'),overlap(a,b,'Z')
						if x>=-.28 and z>=-.28 then put(links,host,(x+.31)*(z+.31)) end
					end
				end
				if role=='band' and next(links)==nil then
					-- The legacy upper solid doubles as the backing for
					-- decorative floor bands on floors without a slab.
					for _,host in hosts do
						local b=host.Box
						if gap(a,b,'Y')<=.9 then
							local x,z=overlap(a,b,'X'),overlap(a,b,'Z')
							if x>=-.30 and z>=-.30 then put(links,host,(x+.34)*(z+.34)) end
						end
					end
				end
			else
				local anchor=nil
				if role=='window' then
					local score=math.huge
					for _,pane in panes do
						local b=pane.Box
						local normal=if b.NormalX then 'X' else 'Z'
						local tangent=if b.NormalX then 'Z' else 'X'
						local delta=a.Center-b.Center
						local yd,td=gap(a,b,'Y'),gap(a,b,tangent)
						local rank=delta.Magnitude
						if rank<score and math.abs(delta[normal])<=1.3 and yd<=.8 and td<=.8 then
							anchor,score=pane,rank
						end
					end
				end
				if anchor and openingLinks[anchor] then links=openingLinks[anchor]
				else
					local mount=if anchor then anchor.Box else a
					local axis=if mount.NormalX then 'X' else 'Z'
					local span=if mount.NormalX then 'Z' else 'X'
					for _,host in hosts do
						local b=host.Box
						local yn,an,tn=gap(mount,b,'Y'),gap(mount,b,axis),gap(mount,b,span)
						if yn<=(if role=='front' then 2.8 else 1.25) and an<=(if role=='front' then 3.3 else 1.8) and tn<=1 then
							local w=math.max(.16,overlap(mount,b,span)+.65)*math.max(.16,overlap(mount,b,'Y')+.65)
							put(links,host,w/(1+yn+an+tn))
						end
					end
					if anchor then openingLinks[anchor]=links end
				end
			end
			local total=0;for _,w in links do total+=w end
			if total>0 then
				local attachment={Cell=cell,Links=links,Total=total}
				if structuralDeck then
					local seeds=s.Decks[cell.Record]
					if not seeds then seeds={};s.Decks[cell.Record]=seeds end
					table.insert(seeds,attachment)
				else table.insert(s.Attachments,attachment) end
			end
		end
	end
	local function floorAt(s,y)
		if y>=s.Height-.07 then return s.Floors+1 end
		if y<s.Ground then return 1 end
		return math.clamp(math.floor((y-s.Ground)/s.Story)+2,1,s.Floors)
	end
	local function owner(part,geometry)
		local at=part
		local floor
		while at and at~=geometry do
			if at:GetAttribute('BoraElevator')==true then return nil,at end
			local f=tonumber(at.Name:match('^Floor_(%d+)$'))
			if f and not floor then floor=f end
			at=at.Parent
		end
		return floor,nil
	end
	local function record(s,part,manual)
		local explicit,lift=owner(part,s.Geometry)
		if lift then s.Lifts[lift]=true;return end
		local localFrame=s.Base:ToObjectSpace(part.CFrame);local centre=localFrame.Position
		local n,size=part.Name,part.Size
		local interior=manual or partition(part,s.Geometry)
		local role=if not interior then attachmentRole(n) else nil
		local floor=explicit or floorAt(s,centre.Y)
		if n=='GroundCeiling' then floor=math.min(2,s.Floors+1)
		elseif n:match('^Roof') or n=='AccessCap' or n:match('^Parapet') or n:match('^Coping') then floor=s.Floors+1 end
		local structuralDeck=role=='roofDeck' or role=='ceiling'
		local split=(isWall(n) or interior or role=='band' or structuralDeck or n=='RoofParapet' or n=='Parapet' or n=='Coping')
			and part:IsA('Part') and part.Shape==E.PartType.Block and #part:GetChildren()==0 and localFrame.UpVector.Y>.98
		local xLong=size.X>=size.Z
		local length=if xLong then size.X else size.Z
		local width=if xLong then size.Z else size.X
		local count=if split then math.clamp(math.ceil(length/7),1,16) else 1
		local cross=if split and (n=='UpperMasonry' or role=='band' or structuralDeck)
			then math.clamp(math.ceil(width/7),1,16) else 1
		local cuts={-size.Y*.5}
		if split and not explicit then
			for f=2,s.Floors do
				local seam=s.Ground+(f-2)*s.Story-centre.Y
				if seam>cuts[1]+.15 and seam<size.Y*.5-.15 then table.insert(cuts,seam) end
			end
		end
		table.insert(cuts,size.Y*.5)
		local priority=if n=='GroundCeiling' or n:match('^FloorSlab') or n:match('^Roof') then 1 elseif isWall(n) then 2 else 3
		local r={Name=n,Role=role,Source=part,Cells={},Blast=interior or canBlast(part) or role~=nil,Partition=interior,Exposed=false,DropPriority=priority,Parts=s.Parts}
		table.insert(s.Records,r);s.Parts[part]=r
		local side=if math.abs(centre.X)/s.Width>math.abs(centre.Z)/s.Depth then (if centre.X>=0 then 'E' else 'W') else (if centre.Z>=0 then 'S' else 'N')
		for j=2,#cuts do
			local y=(cuts[j]+cuts[j-1])*.5;local height=cuts[j]-cuts[j-1]
			local level=if #cuts>2 then floorAt(s,centre.Y+y) else floor
			for i=1,count do for k=1,cross do
				local step,w=length/count,width/cross
				local a,b=-length*.5+(i-.5)*step,-width*.5+(k-.5)*w
				local cf=part.CFrame*C.new(if xLong then a else b,y,if xLong then b else a)
				local sz=V.new(if xLong then step else w,height,if xLong then w else step)
				local bounds=box(s,cf,sz)
				local localSide=side
				if n=='UpperMasonry' then
					local p=bounds.Center
					localSide=if math.abs(p.X)/s.Width>math.abs(p.Z)/s.Depth then (if p.X>=0 then 'E' else 'W') else (if p.Z>=0 then 'S' else 'N')
				end
				local cell={Record=r,Floor=level,Side=localSide,Frame=cf,Size=sz,Box=bounds,Health=1}
				if not interior and isSupport(n) and level<=s.Floors and height>=(if level==1 then s.Ground else s.Story)*.51 then
					local support=s.Support[level] or {Total=0,Gone=0,Sides={}}
					s.Support[level]=support;cell.Weight=step*w
					support.Total+=cell.Weight
				end
				if structuralDeck then
					cell.Neighbors={}
					local index=#r.Cells+1
					if i>1 then
						local neighbor=r.Cells[index-cross]
						table.insert(neighbor.Neighbors,cell);table.insert(cell.Neighbors,neighbor)
					end
					if k>1 then
						local neighbor=r.Cells[index-1]
						table.insert(neighbor.Neighbors,cell);table.insert(cell.Neighbors,neighbor)
					end
				end
				table.insert(r.Cells,cell);table.insert(s.Cells,cell)
			end end
		end
		return r
	end
	function D.register(building)
		local old=states[building];if old and old.Geometry.Parent==building then return old end
		if building:GetAttribute('AssetKind')~='BoraBuilding' then return nil end
		local geometry,origin=building:FindFirstChild('Geometry'),building:FindFirstChild('BuildingOrigin')
		if not geometry or not origin or not origin:IsA('BasePart') then return nil end
		local s={Building=building,Geometry=geometry,Base=origin.CFrame,Width=prop(building,'BB_Width',12)/.28,
			Depth=prop(building,'BB_Depth',10)/.28,Ground=prop(building,'BB_GroundHeight',3.45)/.28,
			Story=prop(building,'BB_FloorHeight',3.05)/.28,Floors=math.floor(prop(building,'BB_Floors',3)),
			Support={},Records={},Cells={},Parts={},Lifts={},Attachments={},Decks={},DropFloor=math.huge,Generation=0}
		s.Height=s.Ground+(s.Floors-1)*s.Story
		for _,part in building:GetDescendants() do
			if part:IsA('BasePart') and part.Anchored and part.Transparency<1 then
				if part:IsDescendantOf(geometry) then
					local extra=not canBlast(part) and not attachmentRole(part.Name) and wallPart(part) and (namedWall(part) or uprightWall(part))
					record(s,part,extra)
				elseif part~=origin and wallPart(part) and (namedWall(part) or uprightWall(part)) then record(s,part,true) end
			end
		end
		table.sort(s.Cells,function(a,b) return a.Record.DropPriority<b.Record.DropPriority end)
		initAttachments(s)
		states[building]=s;return s
	end
	local function expose(r)
		if r.Exposed then return true end
		local original=r.Source
		if not original.Parent then return false end
		if #r.Cells==1 then r.Cells[1].Part=original;r.Exposed=true;return true end
		local marks=I.new('Folder');marks.Name=original.Name..'_Sections'
		for _,cell in r.Cells do
			local p=make(original,cell.Frame,cell.Size,false,'WallRemainder')
			p.Parent=marks;cell.Part=p;r.Parts[p]=r
		end
		marks.Parent=original.Parent;r.Exposed=true;r.Parts[original]=nil;original:Destroy();return true
	end
	local function shed(cell,point,collapse,incoming)
		if cell.Gone or not expose(cell.Record) or not cell.Part.Parent then return false end
		cell.Gone=true
		local part=cell.Part;local cf,size=part.CFrame,part.Size
		cell.Record.Parts[part]=nil
		local attached=cell.Record.Role
		if collapse and not attached and not part.CanCollide and part.Material~=E.Material.Glass then part:Destroy();return true end
		if not effects.HasRoom(collapse) then part:Destroy();return true end
		local away=cf.Position-point;local horizontal=V.new(away.X,0,away.Z)
		local direction=if horizontal.Magnitude>.01 then horizontal.Unit else cf.RightVector
		if incoming then
			local normal=if size.X<=size.Z then cf.RightVector else cf.LookVector
			local sign=math.sign(incoming:Dot(normal))
			if sign~=0 then direction=normal*sign end
		end
		local maxSpan=math.max(size.X,size.Z)
		if (attached and attached~='roofDeck' and maxSpan<10 and size.Y<9) or ((maxSpan<4.5 and size.Y<5) and part.CanCollide and part.Transparency<.8) then
			if attached then part.CanCollide=true end
			effects.Release(part,direction*(if collapse then 2.4 else 16)+V.yAxis*(if collapse then -2 else 6),V.new(.6,1.6,-.8),collapse)
		else
			local nx=math.clamp(math.ceil(size.X/(if collapse then 7 else 3)),1,4)
			local ny=math.clamp(math.ceil(size.Y/(if collapse then 5 else 3.4)),1,3)
			local nz=math.clamp(math.ceil(size.Z/(if collapse then 7 else 3)),1,4)
			local sx,sy,sz=size.X/nx,size.Y/ny,size.Z/nz
			for x=1,nx do for y=1,ny do for z=1,nz do
				if effects.HasRoom(collapse) and part.Transparency<.8 then
					local k=x*13+y*7+z*5
					local f=cf*C.new(-size.X*.5+(x-.5)*sx,-size.Y*.5+(y-.5)*sy,-size.Z*.5+(z-.5)*sz)
					local fragment=make(part,f,V.new(math.max(.07,sx*.955),math.max(.07,sy*.94),math.max(.07,sz*.955)),k%3==0,'BuildingFragment')
					fragment.CanCollide=true
					effects.Release(fragment,direction*(if collapse then 1.6+(k%3) else 12+(k%8))+V.yAxis*(if collapse then -3 else 3+k%5),V.new(k%3-1,1.2,k%5-2),collapse)
				end
			end end end
			part:Destroy()
		end
		return true
	end
	local function hasSupport(attachment)
		local alive=0
		for host,w in attachment.Links do if not host.Gone then alive+=w end end
		return alive>=attachment.Total*.30
	end
	local function dropUnsupported(s,point,inCollapse)
		local count=0
		for record,seeds in s.Decks do
			-- Interior slab tiles also rest on walls through their surviving neighbors.
			local supported,queue={},{}
			for _,seed in seeds do
				if not seed.Cell.Gone and hasSupport(seed) then
					supported[seed.Cell]=true;table.insert(queue,seed.Cell)
				end
			end
			local i=1
			while i<=#queue do
				for _,neighbor in queue[i].Neighbors do
					if not neighbor.Gone and not supported[neighbor] then
						supported[neighbor]=true;table.insert(queue,neighbor)
					end
				end
				i+=1
			end
			for _,cell in record.Cells do
				if not cell.Gone and not supported[cell] and shed(cell,point,inCollapse) then count+=1 end
			end
		end
		for _,attachment in s.Attachments do
			local cell=attachment.Cell
			if not cell.Gone and not hasSupport(attachment) and shed(cell,point,inCollapse) then count+=1 end
		end
		return count
	end
	local function punch(record,part,point,from)
		-- Hit identity wins over the radius scan. Near a doorway or from a
		-- thin edge, select the precise surviving cell that stopped the rocket.
		local closest,dist=nil,math.huge
		for _,cell in record.Cells do if not cell.Gone then
			local d=D.distance(cell.Frame,cell.Size,point)
			if cell.Part==part then closest=cell;break end
			if d<dist then closest,dist=cell,d end
		end end
		if not closest then return 0 end
		if effects.BeforePartition then effects.BeforePartition() end
		return if shed(closest,point,false,from and point-from) then 1 else 0
	end
	local owners={BoraRoads=true,BoraVehicles=true,BoraTrees=true,BoraMapReference=true,BoraRocketPlay=true,BoraNeighborhood_01=true}
	function D.hitStandalone(part,point,from)
		local r=part and looseWalls[part]
		if r then return punch(r,part,point,from) end
		if not part or not wallPart(part) or not namedWall(part) then return 0 end
		local at=part.Parent
		while at do if owners[at.Name] then return 0 end;at=at.Parent end
		local base=part.CFrame
		local s={Base=base,Geometry=part.Parent,Width=part.Size.X,Depth=part.Size.Z,Floors=1,Ground=20,Story=12,Height=20,
			Lifts={},Support={},Records={},Cells={},Parts=looseWalls}
		r=record(s,part,true)
		return if r then punch(r,part,point,from) else 0
	end
	local function failFloor(s)
		local collapse=math.huge
		for floor,support in s.Support do
			local damaged=0;for _ in support.Sides do damaged+=1 end
			if support.Total>0 and damaged>=2 and (support.Total-support.Gone)/support.Total<=D.SupportLimit then
				collapse=math.min(collapse,floor+1)
			end
		end
		return collapse
	end
	local function collapse(s,from,point)
		if from>=s.DropFloor then return end
		s.DropFloor=from;s.Generation+=1;local generation=s.Generation
		s.Building:SetAttribute('BoraCollapseFromFloor',from)
		for level=from,s.Floors+1 do
			effects.Schedule(.23+(level-from)*.24,function()
				if generation~=s.Generation or s.Geometry.Parent~=s.Building then return end
				if level==from then for lift in s.Lifts do if lift.Parent then lift:Destroy() end end end
				if effects.BeforeDrop then effects.BeforeDrop(level) end
				local count=0
				for _,cell in s.Cells do
					if cell.Floor==level and not cell.Gone then
						if shed(cell,point,true) then count+=1 end
					end
				end
				count+=dropUnsupported(s,point,true)
				if count>0 then effects.Collapse(s.Building,level,count) end
			end)
		end
	end
	function D.blast(building,point,hitPart,from)
		local s=D.register(building);if not s then return 0 end
		local direct=hitPart and s.Parts[hitPart]
		if not direct and hitPart and hitPart:IsDescendantOf(building) and wallPart(hitPart) then
			local inside=hitPart:IsDescendantOf(s.Geometry)
			local extra=(not inside or not canBlast(hitPart)) and (namedWall(hitPart) or uprightWall(hitPart))
			if (inside and partition(hitPart,s.Geometry)) or extra then
				direct=record(s,hitPart,extra)
			end
		end
		if direct and direct.Partition then return punch(direct,hitPart,point,from) end
		local destroyed=0
		for _,cell in s.Cells do
			local r=cell.Record
			if not cell.Gone and r.Blast then
				local distance=D.distance(cell.Frame,cell.Size,point)
				if distance<=D.BlastRadius then
					cell.Health-=math.max(.18,1.65-distance/D.BlastRadius*1.40)
					if (cell.Health<=0 or (hitPart and (hitPart==cell.Part or (hitPart==r.Source and distance<.12)))) and shed(cell,point,false) then
						destroyed+=1
						local support=s.Support[cell.Floor]
						if cell.Weight and support then support.Gone+=cell.Weight;support.Sides[cell.Side]=true end
					end
				end
			end
		end
		local from=failFloor(s)
		destroyed+=dropUnsupported(s,point,false)
		if from<math.huge then collapse(s,from,point) end
		return destroyed
	end
	return D
end
