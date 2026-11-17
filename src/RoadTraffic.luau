-- Distances in the inspector are meters. Markings follow the actual road
-- samples beyond each junction portal, including slopes and curved approaches.
return function(api,Path,LaneDirections,Assets)
	local V,Instance,CFrame,Color3,Enum=api.Vector3,api.Instance,api.CFrame,api.Color3,api.Enum
	local T={}
	assert(Assets and Assets.Vehicle and Assets.Pedestrian,'Missing measured signal asset layout')
	T.AssetLayout=Assets
	T.Defaults={Crosswalks=true,StopLines=true,Signals=true,PedestrianSignals=true,CrosswalkWidth=3,CrosswalkOffset=.6,StopGap=1,GreenSeconds=12,LeftSeconds=8,WalkSeconds=10,FlashSeconds=4}
	T.Limits={CrosswalkWidth={2,6},CrosswalkOffset={0,5},StopGap={.5,4},GreenSeconds={5,60},LeftSeconds={4,40},WalkSeconds={6,60},FlashSeconds={2,10}}
	function T.normalize(input)
		local out={}
		for key,value in T.Defaults do
			local x=if input[key]==nil then value else input[key]
			if type(value)=='boolean' then assert(type(x)=='boolean',key..' 설정을 확인하세요.')
			else local bounds=T.Limits[key]; assert(type(x)=='number' and x==x and x>=bounds[1] and x<=bounds[2],key..' 범위를 확인하세요.') end
			out[key]=x
		end
		return out
	end
	function T.config(folder)
		local input={}; for key in T.Defaults do input[key]=folder:GetAttribute(key) end
		return T.normalize(input)
	end
	function T.savedMask(junction,index)
		local rules=junction:FindFirstChild('LaneDirections')
		if rules then for _,rule in rules:GetChildren() do if rule:GetAttribute('Arm')==index then
			local mask=0
			for lane=1,rule:GetAttribute('Count') or 0 do mask=bit32.bor(mask,rule:GetAttribute('Lane'..lane) or 0) end
			if mask>0 then return mask end
		end end end
	end
	local function section(arm,outward)
		local s=Path.at(arm.Data,arm.Anchor+arm.Sign*(arm.Trim+outward))
		local p=s.P+V.yAxis*(arm.Data.Config.Lift*Path.StudsPerMeter+.045)
		return p,s.Side*(arm.Sign*s.Miter)
	end
	function T.plan(plan,input)
		local settings=T.normalize(input); local scale=Path.StudsPerMeter
		local result={Settings=settings,Markings={},Signals={},Pedestrians={},Cuts={},Limited=0}
		local offset=settings.CrosswalkOffset*scale
		local depth=if settings.Crosswalks then settings.CrosswalkWidth*scale else 0
		local stopStart=offset+depth+settings.StopGap*scale
		local reach=if settings.StopLines then stopStart+.4*scale elseif settings.Crosswalks then offset+depth else 0
		for index,arm in plan.Arms do
			local remaining=if arm.Sign==1 then arm.Data.Length-arm.Anchor-arm.Trim else arm.Anchor-arm.Trim
			remaining=math.min(remaining,arm.TrafficRoom or math.huge)
			local paint=reach==0 or remaining>reach+1
			if not paint then result.Limited+=1 end
			local function quad(kind,a,b,left,right)
				local p,u=section(arm,a); local q,v=section(arm,b)
				table.insert(result.Markings,{Kind=kind,Corners={p+u*left,p+u*right,q+v*right,q+v*left},Arm=index})
			end
			if settings.Crosswalks and paint then
				local edge=.2*scale
				local width=2*arm.Half-2*edge
				local n=math.max(2,math.floor(width/scale))
				local pitch=width/n; local stripe=math.min(.5*scale,pitch*.55)
				for i=1,n do
					local lateral=-arm.Half+edge+pitch*(i-.5)
					-- Slice long stripes so they stay on a bend or slope.
					for s=1,3 do quad('Crosswalk',offset+depth*(s-1)/3,offset+depth*s/3,lateral-stripe*.5,lateral+stripe*.5) end
				end
				if settings.PedestrianSignals then
					local p,u=section(arm,offset+depth*.5)
					local lateral=arm.Half+math.max(arm.Walk*.5,.45*scale)
					for _,sign in {-1,1} do
						table.insert(result.Pedestrians,{Position=p+u*(sign*lateral),Direction=-u.Unit*sign,Arm=index,Side=sign})
					end
				end
			end
			if settings.StopLines and paint then
				-- Path.Side is outward-right. Approaching cars use its negative
				-- half in right-hand traffic; a one-lane alley uses its full width.
				local lanes=Path.lanes(arm.Data.Config,arm.Sign)
				local right=if arm.Data.Config.Lanes==1 then arm.Half-.15*scale else arm.Sign*lanes.Divider-.15*scale
				quad('StopLine',stopStart,stopStart+.4*scale,-arm.Half+.15*scale,right)
			end
			if reach>0 and paint then
				local a,b=arm.Anchor+arm.Sign*arm.Trim,arm.Anchor+arm.Sign*(arm.Trim+reach+.15*scale)
				table.insert(result.Cuts,{Approach=arm.Approach,Range={math.min(a,b),math.max(a,b)}})
			end
			if settings.Signals then
				local p,left=section(arm,offset*.5)
				local direction=V.new(left.Z,0,-left.X).Unit
				local phase=if math.abs(arm.Direction:Dot(plan.Arms[1].Direction))>.72 then 1 else 2
				local mask=0
				if plan.LaneRules then for _,value in plan.LaneRules[index].Masks do mask=bit32.bor(mask,value) end
				else
					-- Older callers without lane rules retain straight phases when
					-- there is an opposing exit, turns at a terminating approach.
					for _,other in plan.Arms do if other~=arm then
						local incoming=-arm.Direction
						local cross=incoming.X*other.Direction.Z-incoming.Z*other.Direction.X
						mask=bit32.bor(mask,if incoming:Dot(other.Direction)>.72 then 1 elseif cross<0 then 2 else 4)
					end end
					if bit32.band(mask,1)~=0 then mask=1 end
				end
				table.insert(result.Signals,{Position=p-left*(arm.Half+math.max(arm.Walk*.5,.45*scale)),Direction=direction,Side=left.Unit,Half=arm.Half,Phase=phase,Arm=index,Mask=mask})
			end
		end
		if LaneDirections and plan.LaneRules then LaneDirections.decorate(plan,settings,result,section) end
		plan.Traffic=result
		return result
	end
	local function part(parent,name,size,frame,color,collide)
		local item=Instance.new('Part'); item.Name,item.Size,item.CFrame,item.Color=name,size,frame,color
		item.Anchored,item.CanCollide,item.CanTouch,item.CanQuery=true,collide,false,collide
		item.Material=Enum.Material.SmoothPlastic; item.TopSurface,item.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
		item.Parent=parent; return item
	end
	function T.configureSignal(model,arm,mask)
		assert(mask and mask>=1 and mask<=7,'Missing lane directions for signal')
		model:SetAttribute('Arm',arm);model:SetAttribute('MovementMask',mask)
		model:SetAttribute('SignalProgramVersion',2);model:SetAttribute('RightTurnPolicy','StopAndYield')
		model:SetAttribute('StraightAllowed',false);model:SetAttribute('LeftAllowed',false)
		model:SetAttribute('RightTurnAllowed',false);model:SetAttribute('RightTurnMustYield',bit32.band(mask,4)~=0)
		model:SetAttribute('LightState',nil)
		local scale=Path.StudsPerMeter;local frame=model.TripoHead.CFrame
		for i,name in {'Red','Amber','Green'} do
			local center=if name=='Green' and bit32.band(mask,2)~=0 then Assets.Vehicle.ExtensionCenter else Assets.Vehicle.Centers[i]
			model[name].CFrame=frame*CFrame.new(V.new(table.unpack(center))*scale)
		end
		if bit32.band(mask,2)==0 then return end
		-- Use the third Tripo cup for the arrow, adding a fourth matching
		-- housing for straight green. Keep the existing pole/mount/head intact.
		local housing=model:FindFirstChild('GreenHousing')
		if not housing then housing=part(model,'GreenHousing',V.new(.74,.73,1.15)*scale,frame,Color3.new(1,1,1),false) end
		housing.Size,housing.CFrame,housing.Color=V.new(.74,.73,1.15)*scale,frame,Color3.new(1,1,1)
		local mesh=housing:FindFirstChildOfClass('SpecialMesh')
		if not mesh then mesh=Instance.new('SpecialMesh');mesh.Parent=housing end
		mesh.MeshType=Enum.MeshType.FileMesh;mesh.MeshId='rbxasset://BoraRoadKit/TrafficSignalExtension.mesh'
		mesh.TextureId='rbxasset://BoraRoadKit/TrafficSignal.png';mesh.Scale=V.one*scale
		local center=V.new(table.unpack(Assets.Vehicle.Centers[3]))
		local backing=model:FindFirstChild('LeftBacking') or part(model,'LeftBacking',V.new(.33,.33,.025)*scale,frame,Color3.fromRGB(12,16,14),false)
		backing.CFrame=frame*CFrame.new((center-V.zAxis*.005)*scale)
		local arrow=model:FindFirstChild('Left')
		if not arrow then arrow=Instance.new('Folder');arrow.Name,arrow.Parent='Left',model end
		arrow:SetAttribute('SignalLamp','Left')
		for i,line in {{-.11,0,.10,0},{.10,0,.015,.085},{.10,0,.015,-.085}} do
			local a,b=V.new(line[1],line[2],0),V.new(line[3],line[4],0)
			local delta=b-a
			local segment=arrow:FindFirstChild('Segment'..i) or part(arrow,'Segment'..i,V.new(delta.Magnitude,.035,.015)*scale,frame,Color3.fromRGB(21,25,24),false)
			segment.CFrame=frame*CFrame.new((center-V.zAxis*.032+(a+b)*.5)*scale)*CFrame.Angles(0,0,math.atan2(delta.Y,delta.X))
		end
	end
	local function glyph(parent,frame,center,walking,scale)
		local group=Instance.new('Folder'); group.Name=if walking then 'WalkIcon' else 'StopIcon'; group.Parent=parent
		local color=if walking then Color3.fromRGB(45,245,119) else Color3.fromRGB(255,52,39)
		local points=if walking then {
			{0,.055,-.008,-.005},{-.008,-.005,-.042,-.04},{-.042,-.04,-.065,-.075},
			{-.008,-.005,.026,-.032},{.026,-.032,.06,-.045},
			{0,.05,-.027,.025},{-.027,.025,-.052,.043},{0,.05,.028,.07},{.028,.07,.057,.048},
		} else {
			{0,.06,0,-.015},{-.006,-.015,-.023,-.095},{.006,-.015,.023,-.095},
			{0,.055,-.035,.012},{0,.055,.035,.012},
		}
		local function point(x,y) return center+V.new(x,y,0)*scale end
		for i,line in points do
			local a,b=point(line[1],line[2]),point(line[3],line[4]); local delta=b-a
			local angle=math.atan2(delta.Y,delta.X)
			local item=part(group,'Segment'..i,V.new(delta.Magnitude,.018*scale,.009*scale),frame*CFrame.new((a+b)*.5)*CFrame.Angles(0,0,angle),color,false)
			item.Material=Enum.Material.Neon; item.Transparency=if walking then 1 else 0
		end
		local head=part(group,'Head',V.new(.044,.044,.009)*scale,frame*CFrame.new(point(0,.105)),color,false)
		local sphere=Instance.new('SpecialMesh'); sphere.MeshType=Enum.MeshType.Sphere; sphere.Parent=head
		head.Material=Enum.Material.Neon; head.Transparency=if walking then 1 else 0
	end
	function T.buildPedestrians(parent,plan)
		local folder=Instance.new('Folder'); folder.Name,folder.Parent='PedestrianSignals',parent
		local scale=Path.StudsPerMeter
		for _,signal in plan.Traffic.Pedestrians do
			local model=Instance.new('Model'); model.Name='Pedestrian_'..signal.Arm..'_'..(if signal.Side>0 then 'Right' else 'Left'); model.Parent=folder
			local layout=Instance.new('StringValue');layout.Name='BoraDisplayLayout';layout.Value=Assets.Pedestrian.LayoutJson;layout.Parent=model
			model:SetAttribute('CrosswalkArm',signal.Arm); model:SetAttribute('SignalKind','Pedestrian'); model:SetAttribute('AssetSource','Tripo Studio')
			local pole=signal.Position+V.yAxis*(.12*scale-.045)
			part(model,'Base',V.new(.3,.12,.3)*scale,CFrame.new(pole+V.yAxis*(.06*scale)),Color3.fromRGB(98,103,105),true)
			part(model,'Pole',V.new(.10,2.6,.10)*scale,CFrame.new(pole+V.yAxis*(1.3*scale)),Color3.fromRGB(131,139,139),true)
			local position=pole+V.yAxis*(2.1*scale)+signal.Direction*(.12*scale)
			local frame=CFrame.lookAt(position,position+signal.Direction)
			local head=part(model,'TripoPedestrianHead',V.new(table.unpack(Assets.Pedestrian.Bounds))*scale,frame,Color3.new(1,1,1),false)
			local mesh=Instance.new('SpecialMesh'); mesh.MeshType=Enum.MeshType.FileMesh
			mesh.MeshId='rbxasset://BoraRoadKit/PedestrianSignal.mesh'; mesh.TextureId='rbxasset://BoraRoadKit/PedestrianSignal.png'; mesh.Scale=V.one*scale; mesh.Parent=head
			-- Display centers are calibrated against the generated Tripo mesh.
			glyph(model,frame,V.new(table.unpack(Assets.Pedestrian.Centers[1]))*scale,false,scale)
			glyph(model,frame,V.new(table.unpack(Assets.Pedestrian.Centers[2]))*scale,true,scale)
		end
	end
	function T.buildSignals(parent,plan)
		local folder=Instance.new('Folder'); folder.Name,folder.Parent='Signals',parent
		for _,signal in plan.Traffic.Signals do
			local scale=Path.StudsPerMeter
			local model=Instance.new('Model'); model.Name='Signal_'..signal.Arm
			model:SetAttribute('Phase',signal.Phase); model:SetAttribute('AssetSource','Tripo Studio'); model.Parent=folder
			local poleHeight=5.5*scale
			local pole=signal.Position-V.yAxis*.045
			part(model,'Base',V.new(.48,.18,.48)*scale,CFrame.new(pole+V.yAxis*(.09*scale)),Color3.fromRGB(98,103,105),true)
			part(model,'Pole',V.new(.16*scale,poleHeight,.16*scale),CFrame.new(pole+V.yAxis*(poleHeight*.5)),Color3.fromRGB(131,139,139),true)
			-- The head faces outward toward approaching traffic. Its long local X
			-- axis runs across the lane; its front is local -Z.
			local headPosition=pole+V.yAxis*(poleHeight-.35*scale)+signal.Side*(signal.Half*.7)
			local frame=CFrame.lookAt(headPosition,headPosition+signal.Direction)
			local mount=(pole+V.yAxis*(poleHeight-.35*scale)+headPosition)*.5
			part(model,'Arm',V.new(.13*scale,.13*scale,(headPosition-(pole+V.yAxis*(poleHeight-.35*scale))).Magnitude),CFrame.lookAt(mount,headPosition),Color3.fromRGB(131,139,139),false)
			local head=part(model,'TripoHead',V.new(table.unpack(Assets.Vehicle.Bounds))*scale,frame,Color3.new(1,1,1),false)
			local mesh=Instance.new('SpecialMesh'); mesh.MeshType=Enum.MeshType.FileMesh
			mesh.MeshId='rbxasset://BoraRoadKit/TrafficSignal.mesh'; mesh.TextureId='rbxasset://BoraRoadKit/TrafficSignal.png'
			mesh.Scale=V.one*scale; mesh.Parent=head
			-- Lens positions are calibrated against the generated mesh asset.
			for i,name in {'Red','Amber','Green'} do
				local lens=part(model,name,V.new(.30,.30,.035)*scale,frame*CFrame.new((2-i)*.66*scale,-.03*scale,-.418*scale),if name=='Red' then Color3.fromRGB(255,52,39) else Color3.fromRGB(25,29,28),false)
				if name=='Red' then lens.Material=Enum.Material.Neon end
				local sphere=Instance.new('SpecialMesh'); sphere.MeshType=Enum.MeshType.Sphere; sphere.Parent=lens
				lens:SetAttribute('SignalLamp',name)
			end
			T.configureSignal(model,signal.Arm,signal.Mask)
		end
		T.buildPedestrians(parent,plan)
	end
	return T
end
