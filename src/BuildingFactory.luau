-- Exact modular architecture. Only Geometry is regenerated; root identity and
-- user additions outside Geometry survive editing, including Undo snapshots.
return function(api,P,decorations,Plan,Interior)
	local I,V,C,Color,E=api.Instance,api.Vector3,api.CFrame,api.Color3,api.Enum
	local S=1/.28;local F={Version='1.4.0'}
	local function rgb(hex)
		return Color.fromRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
	end
	local function model(name,parent) local m=I.new('Model');m.Name,m.Parent=name,parent;return m end
	local function part(parent,frame,name,size,pos,color,mat,collide)
		assert(size[1]>0 and size[2]>0 and size[3]>0,'Degenerate building part: '..name)
		local p=I.new('Part');p.Name,p.Size,p.CFrame=name,V.new(table.unpack(size))*S,frame*C.new(V.new(table.unpack(pos))*S)
		p.Anchored,p.CanCollide,p.CanQuery,p.CanTouch=true,collide~=false,collide~=false,false
		p.Color,p.Material=rgb(color),mat or E.Material.Concrete;p.TopSurface,p.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth
		p.Parent=parent;return p
	end
	local function sign(board,text)
		local gui=I.new('SurfaceGui');gui.Name='SignFace';gui.Face=E.NormalId.Front
		gui.CanvasSize,gui.LightInfluence=api.Vector2.new(1400,200),.4;gui.Parent=board
		local t=I.new('TextLabel');t.Name='Lettering';t.Size=api.UDim2.fromScale(1,1);t.BackgroundTransparency=1
		t.Text,t.TextColor3,t.Font,t.TextScaled=text,rgb('F5F1DE'),E.Font.SourceSansBold,true;t.Parent=gui
		local pad=I.new('UIPadding');pad.PaddingLeft,pad.PaddingRight=api.UDim.new(.04,0),api.UDim.new(.04,0);pad.Parent=t
	end
	function F.isBuilding(m) return m:IsA('Model') and m:GetAttribute('AssetKind')=='BoraBuilding' and m:FindFirstChild('BuildingOrigin')~=nil end
	local function slab(parent,p,plan,n,level,base)
		local holes=if Plan then Plan.holes(plan,n) else {}
		if #holes==0 then part(parent,base,'FloorSlab',{p.Width,.18,p.Depth},{0,level-.09,0},p.Trim)
		else for _,t in Plan.tiles(p.Width,p.Depth,holes) do
			part(parent,base,'FloorSlabTile',{t.X1-t.X0,.18,t.Z1-t.Z0},{(t.X0+t.X1)*.5,level-.09,(t.Z0+t.Z1)*.5},p.Trim)
		end end
	end
	function F.retainedInterior(parent,p,base)
		local plan=Plan.decode(p.PlanJSON,p)
		local floors=model('FloorPlanSlabs',parent)
		-- A retained shell supplies the original ground slab and roof.
		for n=2,p.Floors do slab(model('Floor_'..n,floors),p,plan,n,Plan.level(p,n),base) end
		return Interior.create(parent,p,plan,base)
	end
	function F.geometry(config,base)
		local p=P.normalize(config)
		assert(p.PlanJSON=='' or (Plan and Interior),'도면 모듈이 필요합니다. 건물 플러그인을 갱신하세요.')
		local plan=if Plan then Plan.decode(p.PlanJSON,p) else {Items={}}
		local custom=p.PlanJSON~=''
		local g=model('Geometry');g:SetAttribute('BoraGenerated',true)
		local w,d,gh,fh=p.Width,p.Depth,p.GroundHeight,p.FloorHeight
		local h=gh+(p.Floors-1)*fh;local front=-d*.5
		local residential=p.Kind=='Residential' or p.Kind=='Apartment' or p.Kind=='House'
		local masonry=if p.Kind=='Market' or p.Kind=='House' then E.Material.Brick else E.Material.Concrete
		local function q(parent,n,size,pos,color,mat,collide,frame) return part(parent,frame or base,n,size,pos,color or p.Wall,mat,collide) end
		-- Window openings have masonry surrounds, reveals, real glass and an
		-- interior behind them. No solid wall is hidden directly behind a pane.
		local function facade(parent,frame,span,level,height,store,door)
			local bays=math.max(2,math.floor(span/2.7));local pitch=span/bays
			local paneWidth=if store then pitch-.16 else math.min(p.WindowWidth,pitch-.45)
			local bottom=if store then .18 else .86
			local top=if store then height-.82 else math.min(height-.42,bottom+1.65)
			local left=-span*.5
			for bay=1,bays do
				local x=left+(bay-.5)*pitch;local a,b=x-paneWidth*.5,x+paneWidth*.5
				local opening=door and bay==math.ceil(bays*.65)
				local lo,hi=if opening then .02 else bottom,if opening then math.min(2.55,height-.35) else top
				if lo>.02 then q(parent,'WindowApron',{paneWidth,lo,.24},{x,level+lo*.5,.12},p.Wall,masonry,true,frame) end
				q(parent,'WindowLintel',{paneWidth,height-hi,.24},{x,level+(height+hi)*.5,.12},p.Wall,masonry,true,frame)
				if not opening then
					local pane=q(parent,'WindowGlass',{paneWidth-.08,hi-lo-.08,.045},{x,level+(lo+hi)*.5,.105},'91ADB2',E.Material.Glass,true,frame)
					pane.Transparency=.42;pane.Reflectance=.1
					for _,dx in {-paneWidth*.5,0,paneWidth*.5} do q(parent,'WindowMullion',{.055,hi-lo+.07,.13},{x+dx,level+(lo+hi)*.5,.04},p.Accent,E.Material.Metal,false,frame) end
				end
				for _,dx in {-paneWidth*.5,paneWidth*.5} do q(parent,'OpeningReveal',{.06,hi-lo,.26},{x+dx,level+(lo+hi)*.5,.12},p.Trim,nil,false,frame) end
				for _,y in {lo,hi} do q(parent,'WindowRail',{paneWidth+.1,.055,.16},{x,level+y,.015},p.Accent,E.Material.Metal,false,frame) end
				if not store and not opening then q(parent,'WindowSill',{paneWidth+.22,.09,.36},{x,level+lo-.05,.035},p.Trim,nil,false,frame) end
				if opening then
					q(parent,'EntryMat',{paneWidth,.02,.75},{x,level+.025,.55},'4A514D',E.Material.Fabric,false,frame)
					-- Door is held inward: the full central opening remains clear.
					local doorFrame=frame*C.new((a+.02)*S,level*S,.12*S)*C.Angles(0,math.rad(-82),0)*C.new((paneWidth-.08)*.5*S,(hi-lo)*.5*S,0)
					local leaf=q(parent,'OpenDoor',{paneWidth-.08,hi-lo-.08,.055},{0,0,0},p.Accent,E.Material.Metal,false,doorFrame)
					leaf.Transparency=.25
					q(parent,'DoorHandle',{.035,.30,.08},{paneWidth*.5-.15,0,-.055},p.Trim,E.Material.Metal,false,doorFrame)
				end
			end
			local gap=pitch-paneWidth
			for i=0,bays do
				local edge=i==0 or i==bays
				local width=if edge then gap*.5 else gap
				local x=left+i*pitch+(if i==0 then gap*.25 elseif i==bays then -gap*.25 else 0)
				q(parent,'MasonryPier',{width,height,.24},{x,level+height*.5,.12},p.Wall,masonry,true,frame)
			end
		end
		for n=1,p.Floors do
			local floor=model('Floor_'..n,g);floor:SetAttribute('Floor',n)
			local level=if n==1 then 0 else gh+(n-2)*fh;local height=if n==1 then gh else fh
			slab(floor,p,plan,n,level,base)
			for _,side in {-1,1} do
				q(floor,'FloorBand',{w+.08,.12,.20},{0,level+.02,side*(d*.5-.06)},p.Trim,nil,false)
				q(floor,'FloorBand',{.20,.12,d-.32},{side*(w*.5-.06),level+.02,0},p.Trim,nil,false)
			end
			local frontFrame=base*C.new(0,0,front*S)
			local rearFrame=base*C.new(0,0,d*.5*S)*C.Angles(0,math.pi,0)
			facade(floor,frontFrame,w,level,height,n==1 and not residential,n==1)
			facade(floor,rearFrame,w,level,height,false,false)
			for _,side in {-1,1} do
				local sideFrame=base*C.new(side*w*.5*S,0,0)*C.Angles(0,-side*math.pi*.5,0)
				facade(floor,sideFrame,d-.48,level,height,false,false)
			end
			-- Interior depth visible through glass, without claiming complete flats.
			if not custom then
				q(floor,'RearInteriorPartition',{w-.55,height-.2,.12},{0,level+height*.5,d*.24},'D9D5C9')
				q(floor,'LobbyPartition',{.12,height-.2,d*.40},{w*.18,level+height*.5,d*.02},'D9D5C9')
			end
			if p.Balconies and n>1 then
				local balconyWidth=math.min(w-.8,5.2);local railZ=front-.92
				q(floor,'BalconySlab',{balconyWidth,.15,1.05},{0,level+.02,front-.44},p.Trim)
				q(floor,'BalconyFrontRail',{balconyWidth,.055,.055},{0,level+1.05,railZ},p.Accent,E.Material.Metal,false)
				for _,side in {-1,1} do q(floor,'BalconySideRail',{.055,.055,.95},{side*balconyWidth*.5,level+1.05,front-.45},p.Accent,E.Material.Metal,false) end
				local count=math.ceil(balconyWidth/.23)
				for i=0,count do q(floor,'BalconyPicket',{.035,.95,.035},{-balconyWidth*.5+i*balconyWidth/count,level+.56,railZ},p.Accent,E.Material.Metal,false) end
			end
		end
		local roof=model('Roof',g)
		q(roof,'RoofSlab',{w+.22,.20,d+.22},{0,h+.10,0},p.Trim)
		for _,side in {-1,1} do
			q(roof,'Parapet',{w,.54,.18},{0,h+.43,side*(d*.5-.09)})
			q(roof,'Parapet',{.18,.54,d-.36},{side*(w*.5-.09),h+.43,0})
			q(roof,'Coping',{w-.48,.065,.30},{0,h+.73,side*(d*.5-.09)},p.Trim,nil,false)
			q(roof,'Coping',{.30,.065,d+.12},{side*(w*.5-.09),h+.73,0},p.Trim,nil,false)
		end
		q(roof,'RoofAccess',{1.9,2.1,2.1},{w*.26,h+1.25,d*.22})
		q(roof,'AccessCap',{2.10,.12,2.30},{w*.26,h+2.36,d*.22},p.Trim)
		q(roof,'RoofDoor',{.85,1.8,.06},{w*.26,h+1.13,d*.22-1.08},p.Accent,E.Material.Metal,false)
		if p.Sign then
			local board=q(g,'ShopSign',{w-.5,.64,.16},{0,gh-.42,front-.14},p.Accent,E.Material.SmoothPlastic,false)
			sign(board,p.Title)
		end
		if p.Awning and not residential then
			local a=model('Awning',g);local span=w-.32;local count=math.ceil(span/.8);local pitch=span/count
			for i=1,count do
				local canopy=q(a,'CanvasPanel',{pitch,.055,1.12},{-span*.5+(i-.5)*pitch,gh-1.05,front-.54},if i%2==1 then p.Accent else 'E5DDC5',E.Material.Fabric,false)
				canopy.CFrame=canopy.CFrame*C.Angles(math.rad(-8),0,0)
			end
			q(a,'Valance',{span,.16,.035},{0,gh-1.20,front-1.1},p.Accent,E.Material.Fabric,false)
		end
		if p.Apron>0 then
			local court=model('Forecourt',g)
			q(court,'Paving',{w+.7,.12,p.Apron},{0,-.06,front-p.Apron*.5},'B7B5A9',E.Material.Pavement)
			for x=-math.floor(w*.5),math.floor(w*.5) do q(court,'PavingJoint',{.012,.005,p.Apron},{x,.004,front-p.Apron*.5},'97998F',nil,false) end
		end
		if p.Details then
			local details=model('Details',g)
			for _,x in {-w*.5+.4,w*.5-.4} do
				-- A measured decoration can be replaced by a cleaned asset template.
				if decorations and decorations:FindFirstChild('WallSconce') then
					local lamp=decorations.WallSconce:Clone();lamp.Parent=details
					local target=base*C.new(x*S,2.25*S,(front-.02)*S)
					for _,piece in lamp:GetDescendants() do if piece:IsA('BasePart') then piece.CFrame=target*piece.CFrame end end
				else
					q(details,'SconceBack',{.12,.34,.05},{x,2.25,front-.025},'303A3C',E.Material.Metal,false)
					q(details,'SconceDiffuser',{.13,.24,.12},{x,2.25,front-.1},'E7DDC4',E.Material.SmoothPlastic,false)
				end
			end
			for _,x in {-w*.28,w*.28} do
				q(details,'Condenser',{.95,.65,.5},{x,h+.55,d*.2},'B3B8B4',E.Material.Metal,false)
				for i=1,6 do q(details,'CondenserLouvre',{.78,.028,.025},{x,h+.3+i*.075,d*.2-.265},'3B4546',E.Material.Metal,false) end
			end
			-- Small fittings distinguish a shop from a residential entrance.
			if residential then
				for i=1,4 do q(details,'Mailbox',{.28,.22,.12},{-w*.24+(i-2.5)*.30,1.20,front-.09},p.Accent,E.Material.Metal,false) end
			elseif not custom then
				q(details,'ShopCounter',{w*.26,1,.62},{-w*.22,.5,front+2.0},p.Accent,E.Material.Wood)
				q(details,'CounterTop',{w*.26+.08,.07,.76},{-w*.22,1.035,front+2.0},'99734E',E.Material.Wood,false)
				for i=1,3 do q(details,'DisplayShelf',{w*.34,.06,.32},{-w*.23,.55+i*.42,d*.24-.24},p.Trim,E.Material.Wood,false) end
			end
			if p.Kind=='Cafe' and p.Apron>=2.4 then
				for _,x in {-w*.30,-w*.06} do
					local z=front-p.Apron*.55
					q(details,'CafeTableTop',{.72,.07,.65},{x,.76,z},'99734E',E.Material.Wood)
					q(details,'CafeTableLeg',{.07,.72,.07},{x,.36,z},p.Accent,E.Material.Metal)
					for _,side in {-1,1} do
						q(details,'CafeChairSeat',{.38,.06,.38},{x,.44,z+side*.52},p.Accent,E.Material.Wood)
						q(details,'CafeChairBack',{.38,.32,.05},{x,.64,z+side*.69},p.Accent,E.Material.Wood,false)
						for _,dx in {-.14,.14} do q(details,'CafeChairLeg',{.04,.42,.04},{x+dx,.21,z+side*.52},p.Accent,E.Material.Metal,false) end
					end
				end
			elseif p.Kind=='Pharmacy' then
				local board=q(details,'PharmacyBlade',{.58,.58,.10},{w*.5+.28,gh-.14,front+.2},p.Accent,E.Material.SmoothPlastic,false)
				board.CFrame=board.CFrame*C.Angles(0,math.pi*.5,0);sign(board,'+')
			elseif p.Kind=='Market' and p.Apron>=1.2 then
				for i=1,3 do
					q(details,'ProduceCrate',{.56,.42,.48},{-w*.30+(i-2)*.65,.23,front-.46},'99734E',E.Material.Wood)
					for n=1,3 do local fruit=q(details,'Produce',{.14,.14,.14},{-w*.30+(i-2)*.65+(n-2)*.15,.50,front-.46},if i==2 then 'D3A040' else '91A251',E.Material.SmoothPlastic,false);fruit.Shape=E.PartType.Ball end
				end
			end
		end
		if custom then Interior.create(g,p,plan,base) end
		return g,p
	end
	function F.create(config,base)
		local geometry,p=F.geometry(config,base)
		local b=model('보라 '..P.KindLabels[table.find(P.Kinds,p.Kind)])
		local origin=part(b,base,'BuildingOrigin',{.08,.08,.08},{0,0,0},'FFFFFF',nil,false)
		origin.Transparency=1;origin.Locked=true;b.PrimaryPart=origin
		geometry.Parent=b;P.write(b,p);return b
	end
	function F.keepsShell(b,p)
		local geometry=b:FindFirstChild('Geometry')
		if not geometry or geometry:GetAttribute('BoraRetainedShell')~=true then return false end
		local old=P.read(b)
		for key,value in p do if key~='PlanJSON' and value~=old[key] then return false end end
		return true
	end
	function F.rebuild(b,config)
		assert(F.isBuilding(b),'보라 건물을 하나 선택하세요.')
		local old=b:FindFirstChild('Geometry');assert(old and old:GetAttribute('BoraGenerated')==true,'생성 부품 폴더를 확인하세요.')
		local p=P.normalize(config);local base=b.BuildingOrigin.CFrame
		local geometry
		if F.keepsShell(b,p) then
			Plan.decode(p.PlanJSON,p)
			geometry=old:Clone()
			for _,name in {'FloorPlanSlabs','FloorPlanInterior'} do local layer=geometry:FindFirstChild(name);if layer then layer:Destroy() end end
			F.retainedInterior(geometry,p,base)
		else geometry,p=F.geometry(p,base) end
		old.Parent=nil;geometry.Parent=b;P.write(b,p)
		return old
	end
	return F
end
