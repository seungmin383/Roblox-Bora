-- A small permanent street block made from editable Roblox geometry.
return function(api)
	local I,V,C,E,Color=api.Instance,api.Vector3,api.CFrame,api.Enum,api.Color3
	local S=1/.28
	local F={Revision=1}
	local palette={Metal={48,58,60},Stone={190,187,175},Paving={183,181,169},Glass={117,155,159},Wood={123,85,52},Leaf={89,112,69}}
	local function rgb(c) return Color.fromRGB(table.unpack(c)) end
	local function model(parent,name) local o=I.new('Model');o.Name,o.Parent=name,parent;return o end
	local function part(parent,name,size,frame,color,material,collide)
		local p=I.new('Part');p.Name,p.Size,p.CFrame,p.Parent=name,V.new(table.unpack(size))*S,frame,parent
		p.Color=rgb(color);p.Material=material or E.Material.Concrete
		p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,collide~=false,false,collide~=false
		p.TopSurface,p.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth
		return p
	end
	local function localPart(parent,base,name,size,pos,color,material,collide,rotation)
		return part(parent,name,size,base*C.new(V.new(table.unpack(pos))*S)*(rotation or C.new()),color,material,collide)
	end
	local function label(board,text,color)
		local gui=I.new('SurfaceGui');gui.Name='SignFace';gui.Face=E.NormalId.Front;gui.CanvasSize=api.Vector2.new(1000,220)
		gui.LightInfluence=.5;gui.SizingMode=E.SurfaceGuiSizingMode.FixedSize;gui.Parent=board
		local t=I.new('TextLabel');t.Name='Lettering';t.Size=api.UDim2.fromScale(1,1);t.BackgroundTransparency=1
		t.Text,t.TextColor3,t.TextScaled,t.Font=text,rgb(color),true,E.Font.SourceSansBold;t.Parent=gui
	end
	local function window(parent,base,x,y,z,w,h,trim)
		localPart(parent,base,'WindowRecess',{w+.18,h+.18,.08},{x,y,z-.04},{43,53,57},E.Material.SmoothPlastic,false)
		local g=localPart(parent,base,'WindowGlass',{w,h,.04},{x,y,z-.11},palette.Glass,E.Material.Glass,false)
		g.Transparency=.28;g.Reflectance=.12
		for _,dx in {-w*.5,0,w*.5} do localPart(parent,base,'WindowMullion',{.065,h+.12,.13},{x+dx,y,z-.15},trim,E.Material.Metal,false) end
		for _,dy in {-h*.5,h*.5} do localPart(parent,base,'WindowFrame',{w+.15,.065,.13},{x,y+dy,z-.15},trim,E.Material.Metal,false) end
		localPart(parent,base,'WindowSill',{w+.3,.10,.28},{x,y-h*.5-.08,z-.18},trim,nil,false)
	end
	local function bench(parent,base,x,z)
		local b=model(parent,'TimberBench')
		for _,dx in {-.7,.7} do localPart(b,base,'SteelLeg',{.09,.42,.42},{x+dx,.25,z},palette.Metal,E.Material.Metal) end
		for i=1,4 do localPart(b,base,'SeatSlat',{1.9,.07,.095},{x,.48,z-.22+i*.11},palette.Wood,E.Material.Wood,false) end
		for i=1,3 do localPart(b,base,'BackSlat',{1.9,.11,.06},{x,.62+i*.12,z+.24},palette.Wood,E.Material.Wood,false) end
	end
	local function planter(parent,base,x,z,w)
		local p=model(parent,'LowPlanter')
		localPart(p,base,'StoneTrough',{w,.42,.72},{x,.21,z},palette.Stone)
		localPart(p,base,'Soil',{w-.14,.04,.57},{x,.44,z},{77,68,51},E.Material.Ground,false)
		for i=1,math.floor(w/.45) do
			local leaf=localPart(p,base,'Shrub',{.51,.47,.56},{x-w*.5+.25+(i-1)*.45,.64,z},palette.Leaf,E.Material.Grass,false)
			leaf.Shape=E.PartType.Ball
		end
	end
	local function building(root,plot)
		local b=model(root,plot.Id);b:SetAttribute('BuildingUse',plot.Kind);b:SetAttribute('Floors',plot.Floors)
		local base=plot.Frame;local w,d=plot.Width,plot.Depth;local h=3.45+(plot.Floors-1)*3.05
		local front=-d*.5
		local function q(n,size,pos,color,material,collide,rot) return localPart(b,base,n,size,pos,color,material,collide,rot) end
		q('GroundFloorSlab',{w+.2,.16,d+.2},{0,-.08,0},palette.Stone)
		q('UpperMasonry',{w,h-3.45,d},{0,(h+3.45)*.5,0},plot.Wall,if plot.Kind=='Market' then E.Material.Brick else E.Material.Concrete)
		q('GroundRearWall',{w,3.45,.20},{0,1.725,d*.5-.10},plot.Wall)
		for _,side in {-1,1} do
			if plot.Kind=='Residential' then
				q('GroundSideWall',{.2,3.45,d},{side*(w*.5-.1),1.725,0},plot.Wall)
			else
				q('SideSill',{.2,.28,d},{side*(w*.5-.1),.14,0},plot.Wall)
				q('SideFascia',{.2,.8,d},{side*(w*.5-.1),3.05,0},plot.Wall)
				for _,z in {-d*.5+.1,0,d*.5-.1} do q('CornerPier',{.2,3.45,.20},{side*(w*.5-.1),1.725,z},plot.Wall) end
				for _,z in {-d*.25,d*.25} do
					local g=q('SideStorefrontGlass',{.045,2.35,d*.5-.3},{side*(w*.5-.09),1.45,z},palette.Glass,E.Material.Glass)
					g.Transparency=.55;g.Reflectance=.08
					q('SideMullion',{.08,2.4,.065},{side*(w*.5-.06),1.45,z},plot.Trim,E.Material.Metal,false)
					for _,y in {.28,2.62} do q('SideWindowRail',{.09,.065,d*.5-.25},{side*(w*.5-.06),y,z},plot.Trim,E.Material.Metal,false) end
				end
			end
		end
		q('GroundCeiling',{w,.22,d},{0,3.38,0},plot.Trim)
		-- Recessed storefront, open entrance and real space behind the glass.
		local doorX=w*.19;local doorW=1.25
		for _,span in {{-w*.5,doorX-doorW*.5},{doorX+doorW*.5,w*.5}} do
			local width=span[2]-span[1]-.14;local x=(span[1]+span[2])*.5
			local g=q('StorefrontGlass',{width,2.4,.045},{x,1.42,front+.18},palette.Glass,E.Material.Glass)
			g.Transparency=.55;g.Reflectance=.08
			for _,y in {.22,2.62} do q('StorefrontRail',{width,.07,.10},{x,y,front+.16},plot.Trim,E.Material.Metal,false) end
			for _,dx in {-width*.5,0,width*.5} do q('StorefrontPost',{.065,2.45,.10},{x+dx,1.42,front+.15},plot.Trim,E.Material.Metal,false) end
		end
		for _,dx in {-doorW*.5,doorW*.5} do q('DoorJamb',{.09,2.6,.18},{doorX+dx,1.3,front+.1},plot.Trim,E.Material.Metal) end
		q('DoorLintel',{doorW+.18,.10,.18},{doorX,2.65,front+.1},plot.Trim,E.Material.Metal)
		local doorFrame=base*C.new((doorX-doorW*.5)*S,0,(front+.1)*S)*C.Angles(0,math.rad(-78),0)*C.new(doorW*.5*S,1.3*S,0)
		local door=part(b,'OpenEntryDoor',{doorW,2.5,.06},doorFrame,palette.Glass,E.Material.Glass)
		door.Transparency=.5
		part(b,'DoorHandle',{.04,.35,.06},doorFrame*C.new((doorW*.5-.12)*S,0,-.07*S),palette.Metal,E.Material.Metal,false)
		q('EntryMat',{1.35,.025,.75},{doorX,.015,front+.65},{75,78,69},E.Material.Fabric,false)
		local sign=q('ShopSign',{w-.35,.72,.18},{0,3.05,front-.13},plot.Accent,E.Material.SmoothPlastic,false)
		label(sign,plot.Title,{245,241,222})
		local rear=base*C.new(0,0,d*.5*S)*C.Angles(0,math.pi,0)
		localPart(b,rear,'ServiceDoor',{.95,2.2,.06},{w*.26,1.1,-.045},plot.Accent,E.Material.Metal)
		localPart(b,rear,'ServiceDoorHandle',{.035,.22,.05},{w*.26+.32,1.1,-.095},palette.Metal,E.Material.Metal,false)
		-- Continuous floor bands, window reveals and exposed corner masonry.
		for floor=2,plot.Floors do
			local level=3.45+(floor-2)*3.05
			q('FloorBand',{w+.18,.12,d+.18},{0,level+.05,0},plot.Trim,nil,false)
			local bays=math.floor(w/2.65)
			for bay=1,bays do window(b,base,(bay-(bays+1)*.5)*(w/bays),level+1.6,front,1.65,1.65,plot.Trim) end
			for _,x in {-w*.27,w*.27} do window(b,rear,x,level+1.6,0,1.45,1.45,plot.Trim) end
			for _,side in {-1,1} do
				local sideBase=base*C.new(side*w*.5*S,0,0)*C.Angles(0,-side*math.pi*.5,0)
				for _,z in {-d*.25,d*.25} do window(b,sideBase,z,level+1.6,0,1.45,1.65,plot.Trim) end
			end
		end
		q('RoofCap',{w+.35,.18,d+.35},{0,h+.09,0},plot.Trim)
		for _,side in {-1,1} do
			q('RoofParapet',{w,.45,.15},{0,h+.32,side*(d*.5-.05)},plot.Wall)
			q('RoofParapet',{.15,.45,d},{side*(w*.5-.05),h+.32,0},plot.Wall)
		end
		q('RoofAccess',{2.1,1.9,2},{w*.28,h+.95,d*.22},plot.Wall)
		q('AccessCap',{2.25,.10,2.15},{w*.28,h+1.95,d*.22},plot.Trim)
		for _,x in {-1,1} do
			q('AirConditioner',{1.1,.65,.55},{x*1.1,h+.42,d*.25},{174,179,174},E.Material.Metal,false)
			for i=1,5 do q('CondenserSlat',{.9,.035,.025},{x*1.1,h+.2+i*.08,d*.25-.29},palette.Metal,E.Material.Metal,false) end
		end
		-- Thin paving joins the existing sidewalk; keep a clear central entry.
		local apron=plot.Apron
		q('Forecourt',{w+1.4,.12,apron},{0,-.06,front-apron*.5},palette.Paving,E.Material.Pavement)
		for _,x in {-(w+1.4)*.5,(w+1.4)*.5} do q('PavingEdge',{.12,.015,apron},{x,.01,front-apron*.5},plot.Trim,nil,false) end
		for x=-math.floor(w*.5),math.floor(w*.5),1 do q('PavingJoint',{.018,.008,apron},{x,.005,front-apron*.5},{135,137,129},nil,false) end
		if plot.Kind~='Residential' then
			for i=1,math.floor(w/.85) do
				q('CanvasAwning',{.85,.065,1.25},{-w*.5+(i-.5)*.85,2.67,front-.65},if i%2==0 then plot.Accent else {222,214,188},E.Material.Fabric,false,C.Angles(math.rad(-9),0,0))
			end
			q('AwningValance',{w,.20,.04},{0,2.47,front-1.26},plot.Accent,E.Material.Fabric,false)
		end
		-- Street-facing ground-floor fittings are actual geometry.
		q('Counter',{w*.3,1.0,.65},{-w*.2,.5,front+2.1},plot.Accent,E.Material.Wood)
		q('CounterTop',{w*.3+.1,.08,.8},{-w*.2,1.04,front+2.1},palette.Wood,E.Material.Wood)
		if plot.Kind=='Cafe' then
			for _,x in {-w*.30,-w*.05} do
				q('CafeTable',{.8,.07,.65},{x,.72,front-apron*.55},palette.Wood,E.Material.Wood)
				q('TableLeg',{.08,.7,.08},{x,.35,front-apron*.55},palette.Metal,E.Material.Metal)
				for _,side in {-1,1} do
					q('ChairSeat',{.4,.06,.4},{x,.43,front-apron*.55+side*.58},plot.Accent,E.Material.Wood)
					q('ChairBack',{.4,.38,.05},{x,.64,front-apron*.55+side*.77},plot.Accent,E.Material.Wood,false)
					q('ChairBase',{.09,.4,.09},{x,.2,front-apron*.55+side*.58},palette.Metal,E.Material.Metal)
				end
			end
		elseif plot.Kind=='Residential' then
			for floor=2,plot.Floors do
				local y=3.45+(floor-2)*3.05
				q('BalconySlab',{3.9,.14,.9},{0,y+.12,front-.44},plot.Trim)
				for i=-5,5 do q('BalconyBaluster',{.035,.85,.035},{i*.34,y+.64,front-.88},palette.Metal,E.Material.Metal,false) end
				q('BalconyRail',{3.8,.045,.05},{0,y+1.08,front-.88},palette.Metal,E.Material.Metal,false)
			end
			for i=1,4 do q('Mailbox',{.28,.22,.13},{-.9+i*.3,1.25,front+.25},plot.Accent,E.Material.Metal,false) end
		elseif plot.Kind=='Pharmacy' then
			local cross=q('PharmacyBlade',{.65,.65,.13},{w*.5+.3,3.35,front+.3},plot.Accent,E.Material.SmoothPlastic,false,C.Angles(0,math.pi*.5,0))
			label(cross,'+',{250,249,227})
		else
			for i=1,3 do
				q('ProduceCrate',{.55,.45,.5},{-w*.34+i*.65,.25,front-.42},palette.Wood,E.Material.Wood)
				for n=1,3 do
					local fruit=q('Produce',{.15,.14,.15},{-w*.34+i*.65+(n-2)*.15,.53,front-.42},if i%2==0 then {211,139,52} else {143,161,63},E.Material.SmoothPlastic,false)
					fruit.Shape=E.PartType.Ball
				end
			end
		end
		for row=1,3 do q('InteriorShelf',{w*.35,.08,.32},{-w*.2,.7+row*.45,d*.5-.4},plot.Trim,E.Material.Wood,false) end
		bench(b,base,-w*.32,front-apron+1.25)
		planter(b,base,w*.38,front-apron+1.25,1.5)
	end
	function F.create(plan)
		local root=I.new('Model');root.Name='BoraNeighborhood_01';root:SetAttribute('AssetKind','BoraNeighborhood');root:SetAttribute('DesignRevision',F.Revision)
		local revision=I.new('StringValue');revision.Name='BoraNeighborhoodRevision';revision.Value='1';revision.Parent=root
		root:SetAttribute('JunctionName',plan.Junction);root:SetAttribute('Center',plan.Center)
		local buildings=model(root,'Buildings');local street=model(root,'StreetFurniture');local access=model(root,'CrosswalkApproaches')
		for _,plot in plan.Plots do building(buildings,plot) end
		for i,lamp in plan.Lamps do
			local b=model(street,'StreetLight_'..i);local base=C.lookAt(lamp.Position,lamp.Position+lamp.Direction)
			localPart(b,base,'Foot',{.32,.12,.32},{0,.06,0},palette.Metal,E.Material.Metal)
			localPart(b,base,'Mast',{.11,4.8,.11},{0,2.5,0},palette.Metal,E.Material.Metal)
			localPart(b,base,'Bracket',{.09,.10,.9},{0,4.8,-.4},palette.Metal,E.Material.Metal,false)
			local head=localPart(b,base,'LampHead',{.34,.10,.75},{0,4.76,-.8},palette.Metal,E.Material.Metal,false)
			local lens=localPart(b,base,'WarmLED',{.27,.025,.6},{0,4.69,-.8},{255,230,187},E.Material.Neon,false)
			local light=I.new('PointLight');light.Color=rgb({255,227,187});light.Brightness=.65;light.Range=8*S;light.Shadows=true;light.Parent=lens
		end
		for i,landing in plan.Landings do
			local b=model(access,'TactileLanding_'..i)
			local base=C.lookAt(landing.Position,landing.Position+landing.Direction)
			localPart(b,base,'WarningTile',{2.4,.022,.55},{0,.014,0},{219,181,65},E.Material.Concrete,false)
			for x=-5,5 do for z=-1,1 do
				local dot=localPart(b,base,'RaisedDot',{.065,.018,.065},{x*.20,.035,z*.17},{230,194,76},E.Material.SmoothPlastic,false)
				dot.Shape=E.PartType.Ball
			end end
		end
		return root
	end
	return F
end
