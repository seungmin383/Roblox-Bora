-- Pure geometry recipe, shared by Lune tests and Studio. Y is up.
return function(Vector3, Parameters)
	local Skeleton = {}
	function Skeleton.build(input)
		local config = Parameters.normalize(input)
		local state = config.Seed + 1
		local function random()
			state = state * 48271 % 2147483647
			return state / 2147483647
		end
		local out = { Config = config, Segments = {}, Anchors = {}, Branches = {} }
		local function path(id, parent, points, radii)
			local length = 0
			for i = 1, #points-1 do
				local p0,p1=points[math.max(1,i-1)],points[i]
				local p2,p3=points[i+1],points[math.min(#points,i+2)]
				local tangent0=(p2-p0)*.5
				local tangent1=(p3-p1)*.5
				local count=math.max(1,math.ceil((p2-p1).Magnitude/.65))
				local a,r0=p1,radii[i]*config.Thickness
				for j=1,count do
					local t=j/count; local t2,t3=t*t,t*t*t
					local b=p1*(2*t3-3*t2+1)+tangent0*(t3-2*t2+t)+p2*(-2*t3+3*t2)+tangent1*(t3-t2)
					local r1=(radii[i]+(radii[i+1]-radii[i])*t)*config.Thickness
					table.insert(out.Segments,{A=a,B=b,R0=r0,R1=r1,PathId=id,StartLength=length})
					length+=(b-a).Magnitude
					a,r0=b,r1
				end
			end
			table.insert(out.Branches,{ Id=id, ParentId=parent, Points=points, Radii=radii })
		end
		local trunk = {
			Vector3.new(0,0,0),Vector3.new(.02,.65,.03),Vector3.new(-.08,3,.1),
			Vector3.new(-.15,5.5,.08),Vector3.new(-.08,8,0),Vector3.new(.15,10.5,.1),
			Vector3.new(.28,13,.15),Vector3.new(.23,15.5,.08),Vector3.new(.4,18,0),
		}
		path("trunk",nil,trunk,{1.4,1.08,.9,.74,.6,.45,.32,.19,.09})
		local function center(y)
			for i = 1,#trunk-1 do
				if y >= trunk[i].Y and y <= trunk[i+1].Y then
					return trunk[i]:Lerp(trunk[i+1],(y-trunk[i].Y)/(trunk[i+1].Y-trunk[i].Y))
				end
			end
			return trunk[#trunk]
		end
		local phase = random()*math.pi*2
		for i = 1,config.BranchCount do
			local t = (i-1)/math.max(1,config.BranchCount-1)
			local y = 5.8 + t*8.0 + (random()-.5)*.35
			local theta = phase + (i-1)*2.399963 + (random()-.5)*.25
			local dir = Vector3.new(math.cos(theta),0,math.sin(theta))
			local side = Vector3.new(-dir.Z,0,dir.X)
			local reach = (5.5-2.8*t)*config.Spread*(.92+random()*.16)
			local a = center(y)
			local points = { a, a+dir*.7+Vector3.new(0,.4,0),
				a+dir*reach*.36+side*.12+Vector3.new(0,1.15,0),
				a+dir*reach*.72+side*.3+Vector3.new(0,2.05,0),
				a+dir*reach+side*.45+Vector3.new(0,2.9,0) }
			local radius = .48-.23*t
			local id = "branch-"..i
			path(id,"trunk",points,{radius,radius*.9,radius*.63,radius*.35,.1})
			table.insert(out.Anchors,points[5]+Vector3.new(0,.15,0))
			for j = 1,2 do
				local start = points[3]:Lerp(points[4],if j==1 then .16 else .85)
				local angle = theta+(if j==1 then -.7 else .7)
				local offset = Vector3.new(math.cos(angle),0,math.sin(angle))*(2.2-.55*t)*config.Spread
				local tip = start+offset+Vector3.new(0,1.5,0)
				path(id.."-twig-"..j,id,{start,start+offset*.4+Vector3.new(0,.7,0),tip},
					{radius*.45,radius*.32,.075})
				table.insert(out.Anchors,tip)
			end
		end
		table.insert(out.Anchors,Vector3.new(.4,17.5,0))
		return out
	end
	return Skeleton
end
