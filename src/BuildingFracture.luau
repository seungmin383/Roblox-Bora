-- A local breach in one planar, non-load-bearing interior wall section.
return function(api)
	local I,V,C,E=api.Instance,api.Vector3,api.CFrame,api.Enum
	local F={RubbleLifetime=9,TestSize=V.new(.78,9.5,13.6)}
	local spent=setmetatable({},{__mode='k'})
	function F.canBreak(wall)
		return wall and not spent[wall] and wall:IsA('Part') and wall.Shape==E.PartType.Block and wall.Anchored and wall.CanCollide
			and wall.Size.X<=1.8 and wall.Size.Y>=8.1 and wall.Size.Z>=9 and #wall:GetChildren()==0
	end
	-- Scan ahead of the avatar for a level spot with room for the whole panel.
	-- groundAt and occupied come from the selected Studio session's Workspace.
	function F.frontWall(start,groundAt,occupied)
		local look=start.LookVector;local forward=V.new(look.X,0,look.Z)
		if forward.Magnitude<.001 then forward=V.new(0,0,-1) else forward=forward.Unit end
		local side=forward:Cross(V.yAxis);local size=F.TestSize
		for _,distance in {13,18,24,30} do
			for _,offset in {0,-4,4} do
				local point=start.Position+forward*distance+side*offset
				local base,low=-math.huge,math.huge;local level=true
				for _,shift in {-size.Z*.5,0,size.Z*.5} do
					local hit=groundAt(point+side*shift)
					if hit==nil then level=false;break end
					base=math.max(base,hit);low=math.min(low,hit)
				end
				if level and base-low<=.45 then
					local cf=C.fromMatrix(V.new(point.X,base+size.Y*.5+.025,point.Z),-forward,V.yAxis)
					if not occupied(cf,size) then return cf end
				end
			end
		end
		return nil
	end
	function F.findWall(interior,floor)
		local winner,score=nil,-math.huge
		for _,entry in interior:GetChildren() do
			if entry.Name:match('^PlanWall_%d+$') and entry:GetAttribute('Floor')==floor then
				local sections=if entry:IsA('Part') then {entry} else entry:GetChildren()
				for _,part in sections do
					if (part==entry or part.Name=='WallStart' or part.Name=='WallEnd') and F.canBreak(part) then
						local key=part.Size.Z-(entry:GetAttribute('PlanId') or 0)*1e-7
						if key>score then winner,score=part,key end
					end
				end
			end
		end
		return winner
	end
	-- Complete, disjoint volume partition, with a staggered break edge and paired
	-- triangular pieces. The breach reaches the walking surface.
	function F.layout(size)
		local h=math.min(7.4,size.Y-.65)
		local w=math.min(6.4,size.Z*.70)
		local y0=-size.Y*.5;local z0=-size.Z*.5;local z1=-z0
		local fixed,loose={},{}
		local function add(into,a,b,l,r,wedge)
			table.insert(into,{Y=(a+b)*.5,Z=(l+r)*.5,H=b-a,W=r-l,Wedge=wedge})
		end
		local levels={{.23,-.09,.04,.28,.63},{.26,-.02,-.02,.36,.69},{.29,.07,.07,.27,.60},{.22,.105,-.01,.34,.68}}
		local bottom=y0
		for i,row in levels do
			local top=if i==#levels then y0+h else bottom+h*row[1]
			local left,right=w*(-.5+row[2]),w*(.5+row[3])
			add(fixed,bottom,top,z0,left,false);add(fixed,bottom,top,right,z1,false)
			local cuts={left,left+(right-left)*row[4],left+(right-left)*row[5],right}
			for j=1,3 do add(loose,bottom,top,cuts[j],cuts[j+1],j==(if i%2==0 then 1 else 2)) end
			bottom=top
		end
		add(fixed,y0+h,-y0,z0,z1,false)
		return fixed,loose
	end
	function F.breakWall(wall,impact,rubbleParent,effects)
		if not F.canBreak(wall) or not wall.Parent then return nil,'파손 가능한 벽 구간이 아닙니다.' end
		local fixed,loose=F.layout(wall.Size)
		local base,originalParent=wall.CFrame,wall.Parent
		local side=if base:PointToObjectSpace(impact).X>=0 then 1 else -1
		local width=wall.Size.X
		local remain=I.new('Folder');remain.Name='RemainingWall'
		local rubble=I.new('Folder');rubble.Name='WallRubble'
		local launches={}
		local function make(cell,dynamic,wedge,flip,index)
			local part=I.new(if wedge then 'WedgePart' else 'Part')
			part.Name=if dynamic then 'ConcreteFragment' else 'WallRemainder'
			local seam=if dynamic then .035 else 0
			part.Size=V.new(width-seam,cell.H-seam,cell.W-seam)
			part.CFrame=base*C.new(0,cell.Y,cell.Z)
			if flip then part.CFrame*=C.Angles(math.pi,0,0) end
			part.Anchored=true
			part.CanCollide,part.CanQuery,part.CanTouch=true,not dynamic,false
			part.CollisionGroup=wall.CollisionGroup
			part.Color,part.Material,part.MaterialVariant=wall.Color,wall.Material,wall.MaterialVariant
			part.Transparency,part.Reflectance=wall.Transparency,wall.Reflectance
			part.TopSurface,part.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth
			part.Parent=if dynamic then rubble else remain
			if dynamic then
				local direction=base:VectorToWorldSpace(V.new(-side*(9+index%6),1.8+index%4,cell.Z*(1.2+(index%3)*.22)))
				local spin=base:VectorToWorldSpace(V.new(.6,index%3-.7,side*(index%5-2)*.85))
				table.insert(launches,{Part=part,Direction=direction,Spin=spin})
			end
		end
		for i,cell in fixed do make(cell,false,false,false,i) end
		for i,cell in loose do
			make(cell,true,cell.Wedge,false,i*2)
			if cell.Wedge then make(cell,true,true,true,i*2+1) end
		end
		spent[wall]=true;wall:Destroy()
		remain.Parent=originalParent;rubble.Parent=rubbleParent
		effects.Expire(rubble,F.RubbleLifetime)
		for _,launch in launches do
			local part=launch.Part;part.Anchored=false
			effects.Kick(part,launch.Direction,launch.Spin)
		end
		return {Remainder=remain,Rubble=rubble,Count=#launches}
	end
	return F
end
