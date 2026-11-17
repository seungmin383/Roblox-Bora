-- Native asset parts are grouped around separate functional pivots.
return function(api,Catalog)
	local I,V,C,E,Color=api.Instance,api.Vector3,api.CFrame,api.Enum,api.Color3
	local F={Scale=1/.28}
	function F.create(ground)
		local scale=F.Scale;ground=ground or C.new()
		local car=I.new('Model');car.Name='BoraSedan_S1'
		car:SetAttribute('AssetKind','BoraVehicle');car:SetAttribute('VehicleId','BoraSedan01')
		car:SetAttribute('Version',Catalog.Version or 1);car:SetAttribute('Lifecycle','Empty');car:SetAttribute('Design',Catalog.Design or 'BORA S1 compact sedan')
		local revision=I.new('StringValue');revision.Name='BoraVisualRevision';revision.Value=tostring(Catalog.VisualRevision or 1)..':'..(Catalog.VisualHash or '');revision.Parent=car
		if Catalog.LayoutJson then local layout=I.new('StringValue');layout.Name='BoraModelLayout';layout.Value=Catalog.LayoutJson;layout.Parent=car end
		local function part(name,size,frame,parent,visible)
			local p=I.new('Part');p.Name,p.Size,p.CFrame,p.Parent=name,size,frame,parent
			p.Anchored=false;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Massless=true
			p.Transparency=if visible then 0 else 1;p.TopSurface,p.BottomSurface=E.SurfaceType.Smooth,E.SurfaceType.Smooth
			p.Material=E.Material.SmoothPlastic;return p
		end
		local root=part('Chassis',V.new(1.55,.34,3.75)*scale,ground*C.new(0,.62*scale,0),car,false)
		root.CanCollide,root.CanQuery,root.Massless=true,true,false;root.RootPriority=127
		root.CustomPhysicalProperties=api.PhysicalProperties.new(1,.25,0,100,100)
		car.PrimaryPart=root
		local groups=I.new('Folder');groups.Name,groups.Parent='Components',car
		local mechanics=I.new('Folder');mechanics.Name,mechanics.Parent='Mechanics',car
		local hubs={}
		for name,pivot in Catalog.Pivots do
			local folder=I.new('Model');folder.Name,folder.Parent=name,groups
			local pos=V.new(table.unpack(pivot))*scale
			local hub=part('Pivot',V.one*.06,ground*C.new(pos),folder,false);folder.PrimaryPart=hub;hubs[name]=hub
			local joint=I.new(if name=='Body' then 'Weld' else 'Motor6D');joint.Name=name
			joint.Part0,joint.Part1,joint.C0,joint.C1,joint.Parent=root,hub,root.CFrame:ToObjectSpace(hub.CFrame),C.new(),mechanics
			joint:SetAttribute('ClosedC0',joint.C0)
		end
		for index,item in Catalog.Parts do
			local hub=hubs[item.Group]
			local p=part(item.Material..'_'..index,V.new(table.unpack(item.Bounds))*scale,hub.CFrame,hub.Parent,true)
			p.Color=Color.fromRGB(table.unpack(item.Color));p.Transparency=item.Transparency
			if item.Material=='Paint' or item.Material=='CarPaint' then p.Reflectance=.08 end
			p.CastShadow=item.Material~='Glass'
			if item.Material=='Glass' then p.Material=E.Material.Glass;p.Reflectance=.04 end
			if table.find({'LED','Tail','Amber','Screen'},item.Material) then p.Material=E.Material.Neon end
			if item.RobloxMaterial then p.Material=E.Material[item.RobloxMaterial] end
			local mesh=I.new('SpecialMesh');mesh.MeshType=E.MeshType.FileMesh
			mesh.MeshId='rbxasset://BoraVehicleKit/'..item.File;mesh.Scale=V.one*scale;mesh.Parent=p
			if item.Texture then mesh.TextureId='rbxasset://BoraVehicleKit/'..item.Texture end
			local weld=I.new('WeldConstraint');weld.Part0,weld.Part1,weld.Parent=hub,p,p
		end
		local function marker(name,pos,parent)
			local a=I.new('Attachment');a.Name,a.CFrame,a.Parent=name,C.new(V.new(table.unpack(pos))*scale),parent or root;return a
		end
		local markers=Catalog.Markers or {}
		marker('Eye',markers.Eye or {-.43,1.20-.62,.08});marker('SeatedRoot',markers.SeatedRoot or {-.43,.87-.62,.22})
		marker('OutsideDriver',markers.OutsideDriver or {-1.35,.95-.62,-.02})
		marker('DriverHandle',markers.DriverHandle or {-1.0,.83-.62,.10})
		marker('LeftGrip',{-.16,0,0},hubs.Steering);marker('RightGrip',{.16,0,0},hubs.Steering)
		for code,pos in {FL={-.795,-.02,-1.36},FR={.795,-.02,-1.36},RL={-.795,-.02,1.36},RR={.795,-.02,1.36}} do marker('Suspension'..code,markers['Suspension'..code] or pos) end
		local seat=I.new('VehicleSeat');seat.Name='DriverSeat';seat.Size=V.new(.46,.12,.42)*scale
		seat.CFrame=ground*C.new(V.new(table.unpack(Catalog.SeatPosition or {-.43,.43,.24}))*scale)
		seat.Transparency,seat.CanCollide,seat.CanTouch,seat.Massless=1,false,false,true
		seat.Disabled,seat.HeadsUpDisplay,seat.Torque,seat.MaxSpeed=true,false,0,0;seat.Parent=car
		local weld=I.new('WeldConstraint');weld.Part0,weld.Part1,weld.Parent=root,seat,seat
		local driver=I.new('ObjectValue');driver.Name,driver.Parent='Driver',car
		for _,name in {'DoorFL','DoorFR','DoorRL','DoorRR'} do
			local hub=hubs[name];local point=marker('DoorPrompt',{if name:sub(-1)=='L' then -.09 else .09,0,.62},hub)
			local prompt=I.new('ProximityPrompt');prompt.Name='Interact';prompt.ActionText=if name=='DoorFL' then '탑승' else '문 열기 / 닫기'
			prompt.ObjectText=if name=='DoorFL' then 'BORA 세단 · 운전석' else 'BORA 세단 · '..(if name:sub(5,5)=='F' then '앞문' else '뒷문')
			prompt.KeyboardKeyCode=E.KeyCode.E;prompt.HoldDuration=.15;prompt.MaxActivationDistance=12;prompt.RequiresLineOfSight=false;prompt.Parent=point
		end
		local dash=part('DashboardDisplay',V.new(.32,.005,.13)*scale,ground*C.new(V.new(-.45,.97,-.532)*scale)*C.Angles(math.pi/2,0,0),car,false)
		local dw=I.new('WeldConstraint');dw.Part0,dw.Part1,dw.Parent=root,dash,dash
		local gui=I.new('SurfaceGui');gui.Name,gui.Face,gui.Parent='SpeedDisplay',E.NormalId.Top,dash
		gui.AlwaysOnTop=false;gui.LightInfluence=0;gui.SizingMode=E.SurfaceGuiSizingMode.PixelsPerStud;gui.PixelsPerStud=220
		local label=I.new('TextLabel');label.Name,label.Text,label.Size='Speed','0  km/h',api.UDim2.fromScale(1,1)
		label.BackgroundTransparency=1;label.TextColor3=Color.fromRGB(205,238,255);label.TextScaled=true;label.Font=E.Font.GothamMedium;label.Parent=gui
		gui.SizingMode=E.SurfaceGuiSizingMode.FixedSize;gui.CanvasSize=api.Vector2.new(480,200)
		local function text(parent,name,value,x,y,w,h,color)
			local t=I.new('TextLabel');t.Name,t.Text,t.Parent=name,value,parent;t.Size=api.UDim2.fromScale(w,h);t.Position=api.UDim2.fromScale(x,y)
			t.BackgroundTransparency=1;t.TextColor3=color or Color.fromRGB(209,224,234);t.TextScaled=true;t.Font=E.Font.GothamMedium;return t
		end
		local function rect(parent,x,y,w,h,color)
			local f=I.new('Frame');f.Size=api.UDim2.fromScale(w,h);f.Position=api.UDim2.fromScale(x,y);f.BorderSizePixel=0;f.BackgroundColor3=color;f.Parent=parent;return f
		end
		local background=rect(gui,0,0,1,1,Color.fromRGB(9,16,24));background.ZIndex=0
		label.Size=api.UDim2.fromScale(.40,.37);label.Position=api.UDim2.fromScale(.30,.34)
		text(gui,'Brand','B O R A',.35,.04,.30,.12)
		text(gui,'Gear','P',.46,.19,.08,.16,Color.fromRGB(103,221,228))
		text(gui,'Range','RANGE   342 km',.31,.82,.38,.10)
		text(gui,'RPM','RPM ×1000',.03,.71,.22,.11)
		text(gui,'Fuel','FUEL',.79,.71,.16,.11)
		local blue=Color.fromRGB(75,198,229)
		for i=0,12 do
			local a=math.rad(210-i*20);local tick=rect(gui,.16+math.cos(a)*.105,.46+math.sin(a)*.24,.008,.048,if i<10 then blue else Color.fromRGB(242,104,92));tick.Rotation=-math.deg(a)+90
		end
		for i=0,7 do rect(gui,.81+i*.012,.34,.008,.28,if i<6 then blue else Color.fromRGB(38,54,66)) end
		local center=part('CenterDisplay',V.new(.41,.005,.13)*scale,ground*C.new(V.new(.02,.97,-.532)*scale)*C.Angles(math.pi/2,0,0),car,false)
		local cw=I.new('WeldConstraint');cw.Part0,cw.Part1,cw.Parent=root,center,center
		local screen=I.new('SurfaceGui');screen.Name,screen.Face,screen.Parent='Infotainment',E.NormalId.Top,center;screen.LightInfluence=0;screen.SizingMode=E.SurfaceGuiSizingMode.FixedSize;screen.CanvasSize=api.Vector2.new(620,200)
		rect(screen,0,0,1,1,Color.fromRGB(12,22,32))
		text(screen,'Title','BORA   |   DRIVE',.04,.05,.52,.15)
		text(screen,'Status','주행 준비',.04,.35,.45,.28)
		text(screen,'Subtitle','차량 상태 · 안전 운전',.04,.70,.48,.13,Color.fromRGB(141,166,183))
		rect(screen,.61,.15,.003,.68,Color.fromRGB(44,66,82))
		text(screen,'Media','♫  미디어',.67,.22,.28,.19)
		text(screen,'Climate','22.0°   AUTO',.67,.57,.28,.19,blue)
		if Catalog.Screens then
			for name,spec in Catalog.Screens do
				local display=car[name];local tilt=math.rad(spec.Tilt)
				local normal=V.new(0,math.sin(tilt),math.cos(tilt));local position=V.new(table.unpack(spec.Position))+normal*.0025
				display.Size=V.new(spec.Size[1],spec.Size[2],.002)*scale
				display.CFrame=ground*C.lookAt(position*scale,(position+normal)*scale,V.new(0,math.cos(tilt),-math.sin(tilt)))
			end
			-- Keep the approved navigation graphic; only speed/gear are live overlays.
			screen.Enabled=false;gui.Face=E.NormalId.Front;gui.CanvasSize=api.Vector2.new(1200,480)
			for _,item in gui:GetChildren() do if item:IsA('GuiObject') and item~=label and item.Name~='Gear' then item.Visible=false end end
			label.Size=api.UDim2.fromScale(.19,.31);label.Position=api.UDim2.fromScale(.13,.29)
			label.Text='0';label.BackgroundTransparency=0;label.BackgroundColor3=Color.fromRGB(7,13,19)
			local gear=gui.Gear;gear.Size=api.UDim2.fromScale(.16,.32);gear.Position=api.UDim2.fromScale(.695,.29)
			gear.BackgroundTransparency=0;gear.BackgroundColor3=Color.fromRGB(7,13,19)
			car:SetAttribute('NumericInstrumentSpeed',true)
		end
		car:SetAttribute('MeshTriangles',Catalog.TotalTriangles)
		return car
	end
	return F
end
