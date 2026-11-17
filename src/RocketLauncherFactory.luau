-- Native, texture-free shoulder launcher. The bore and rocket fly towards -Z.
return function(api)
	local I,V,C,E,Color=api.Instance,api.Vector3,api.CFrame,api.Enum,api.Color3
	local F={}
	local dark=Color.fromRGB(44,49,50);local olive=Color.fromRGB(89,99,69);local brass=Color.fromRGB(178,149,78)
	local function piece(parent,name,size,frame,color,round)
		local part=I.new('Part');part.Name,part.Size,part.CFrame,part.Color=name,size,frame,color
		part.Material=E.Material.Metal
		part.CanCollide,part.CanTouch,part.CanQuery,part.Massless=false,false,false,true
		if round then part.Shape=E.PartType.Cylinder end
		part.TopSurface,part.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth
		part.Parent=parent;return part
	end
	function F.model(parent,frame,anchored)
		local handle=piece(parent,'Handle',V.new(.34,1.12,.40),frame,dark)
		handle.Anchored=anchored
		local function body(name,size,pos,color,cylinder)
			local fit=frame*C.new(pos)*(if cylinder then C.Angles(0,math.pi*.5,0) else C.new())
			local p=piece(parent,name,size,fit,color,cylinder);p.Anchored=anchored
			if not anchored then
				local joint=I.new('WeldConstraint');joint.Part0,joint.Part1,joint.Parent=handle,p,p
			end
			return p
		end
		body('LauncherTube',V.new(5.45,.86,.86),V.new(0,.82,-.7),olive,true)
		body('MuzzleRing',V.new(.34,1.05,1.05),V.new(0,.82,-3.43),dark,true)
		body('MuzzleBore',V.new(.025,.72,.72),V.new(0,.82,-3.61),Color.fromRGB(19,22,21),true)
		body('RearBell',V.new(.6,1.18,1.18),V.new(0,.82,2.10),dark,true)
		for _,z in {-2.83,-1.88,1.48} do body('RedBand',V.new(.13,.90,.90),V.new(0,.82,z),brass,true) end
		body('ForwardGrip',V.new(.36,.78,.39),V.new(0,.1,-1.75),dark)
		body('ShoulderRest',V.new(.72,.30,1.06),V.new(0,.24,1.24),dark)
		body('Sight',V.new(.31,.24,.80),V.new(0,1.37,-.7),dark)
		local muzzle=I.new('Attachment');muzzle.Name='Muzzle';muzzle.Position=V.new(0,.82,-3.67);muzzle.Parent=handle
		return handle
	end
	function F.rocket(parent,frame)
		local body=piece(parent,'Rocket',V.new(2.05,.36,.36),frame*C.Angles(0,math.pi*.5,0),olive,true)
		body.Anchored=true
		return body
	end
	return F
end
