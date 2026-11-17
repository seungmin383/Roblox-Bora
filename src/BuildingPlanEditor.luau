-- A top-down Studio canvas. Every completed gesture commits one Undo record.
return function(plugin,services,P,B,bridge)
	local Run,Pointer=services.Run,services.Pointer
	local widget=plugin:CreateDockWidgetPluginGuiAsync('BoraBuildingFloorPlan_v1',DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float,false,true,760,850,620,700))
	widget.Title='건물 층별 도면'
	local root=Instance.new('Frame');root.Size=UDim2.fromScale(1,1);root.BackgroundColor3=Color3.fromRGB(29,35,42);root.Parent=widget
	local function label(parent,value,pos,size)
		local o=Instance.new('TextLabel');o.Text,o.Position,o.Size=value,pos,size;o.BackgroundTransparency=1
		o.TextColor3,o.Font,o.TextSize=Color3.fromRGB(229,235,238),Enum.Font.SourceSans,16;o.TextWrapped=true;o.Parent=parent;return o
	end
	local function button(value,x,y,w)
		local o=Instance.new('TextButton');o.Text,o.Position,o.Size=value,UDim2.fromOffset(x,y),UDim2.fromOffset(w,32)
		o.BackgroundColor3,o.TextColor3,o.Font,o.TextSize=Color3.fromRGB(56,72,81),Color3.new(1,1,1),Enum.Font.SourceSansBold,15;o.Parent=root;return o
	end
	local title=label(root,'건물을 선택하세요',UDim2.fromOffset(16,8),UDim2.new(1,-32,0,25))
	local prev=button('◀',16,40,34);local nextFloor=button('▶',128,40,34)
	prev.Name,nextFloor.Name='PreviousFloor','NextFloor'
	local floorBox=Instance.new('TextBox');floorBox.Position,floorBox.Size=UDim2.fromOffset(55,40),UDim2.fromOffset(68,32)
	floorBox.Name,floorBox.Text,floorBox.ClearTextOnFocus,floorBox.TextSize='FloorNumber','1',false,18;floorBox.Parent=root
	local copy=button('다음 층에 복사',170,40,106);local copyAll=button('전층 복사',283,40,84)
	local undoCopy=button('복사 되돌리기',374,40,101)
	copy.Name,copyAll.Name,undoCopy.Name='CopyFloor','CopyAllFloors','UndoFloorCopy'
	local rotate=button('90° 회전',482,40,60);local remove=button('선택 삭제',549,40,59)
	rotate.Name,remove.Name='RotateSelection','DeleteSelection'
	local tools={};local tool='Select';local floor,rotation=1,0;local selected=nil;local pending=nil;local drag=nil
	for i,spec in {{'Select','선택·이동'},{'Wall','벽 선'},{'Block','벽 블록'},{'Door','문 넣기'},{'Stairs','계단'},{'Elevator','엘리베이터'},{'Erase','지우개'}} do
		tools[spec[1]]=button(spec[2],16+(i-1)*84,80,80)
		tools[spec[1]].Name='PlanTool'..spec[1]
	end
	local function scrubLabel(name,text,x,w)
		local o=button(text,x,122,w);o.Name=name;o.Size=UDim2.fromOffset(w,28)
		o.BackgroundColor3=Color3.fromRGB(46,67,77);o.TextColor3=Color3.fromRGB(216,234,239);o.TextSize=14
		return o
	end
	local thicknessLabel=scrubLabel('WallThicknessScrub','↔ 두께 m',16,85)
	local thickness=Instance.new('TextBox');thickness.Position,thickness.Size=UDim2.fromOffset(105,122),UDim2.fromOffset(65,28)
	local wallThickness=B.WallDefault
	thickness.Name,thickness.Text,thickness.ClearTextOnFocus,thickness.TextSize='WallThickness',tostring(wallThickness),false,16;thickness.Parent=root
	local hint=label(root,'↔ 라벨을 좌우로 드래그 · 전층 복사는 다른 층 덮어쓰기',UDim2.fromOffset(16,151),UDim2.new(1,-32,0,14));hint.TextSize=13
	local function field(name,text,x,w)
		local caption=scrubLabel(name..'Scrub',text,x,w)
		local o=Instance.new('TextBox');o.Name,o.Position,o.Size=name,UDim2.fromOffset(x+w+3,122),UDim2.fromOffset(83-w,28)
		o.ClearTextOnFocus,o.TextSize,o.Text=false,15,'—';o.Parent=root;return o,caption
	end
	local pivotX,labelX=field('PivotX','↔ X',181,31);local pivotZ,labelZ=field('PivotZ','↔ Z',277,31)
	local pivotAngle,labelAngle=field('PivotAngle','↔ 각도',373,49)
	local applyPivot=button('값 적용',485,122,100);applyPivot.Name='ApplyPivot'
	local canvas=Instance.new('Frame');canvas.Name='FloorPlanCanvas';canvas.BorderSizePixel=0
	canvas.Position,canvas.Size=UDim2.fromOffset(16,168),UDim2.new(1,-32,1,-250);canvas.ClipsDescendants=true;canvas.BackgroundColor3=Color3.fromRGB(38,47,57);canvas.Parent=root
	local drawing=Instance.new('Frame');drawing.Size=UDim2.fromScale(1,1);drawing.BackgroundTransparency=1;drawing.Parent=canvas
	local hover=Instance.new('Frame');hover.Size=UDim2.fromScale(1,1);hover.BackgroundTransparency=1;hover.Parent=canvas
	local gizmo=Instance.new('Frame');gizmo.Name='PlanPivot';gizmo.Size=UDim2.fromScale(1,1);gizmo.BackgroundTransparency=1;gizmo.ZIndex=20;gizmo.Visible=false;gizmo.Parent=canvas
	-- One topmost surface owns all Studio pointer events. Visual controls must
	-- not consume a press that the canvas would otherwise use for picking.
	local surface=Instance.new('Frame');surface.Name='PlanInput';surface.Size=UDim2.fromScale(1,1)
	surface.BackgroundTransparency,surface.Active,surface.ZIndex,surface.Parent=1,true,30,canvas
	local ring=Instance.new('Frame');ring.Name='RotationRing';ring.Size=UDim2.fromOffset(104,104);ring.AnchorPoint=Vector2.new(.5,.5);ring.BackgroundTransparency=1;ring.ZIndex=21;ring.Parent=gizmo
	local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(1,0);corner.Parent=ring
	local outline=Instance.new('UIStroke');outline.Color=Color3.fromRGB(235,191,83);outline.Thickness=2;outline.Transparency=.15;outline.Parent=ring
	local gizmoHandles={};local handlePositions={}
	for _,spec in {{'X','▶',Color3.fromRGB(218,103,99)},{'XNegative','◀',Color3.fromRGB(218,103,99)},
		{'Z','▲',Color3.fromRGB(90,164,220)},{'ZNegative','▼',Color3.fromRGB(90,164,220)},
		{'Move','✥',Color3.fromRGB(223,231,220)},{'Rotate','↻',Color3.fromRGB(235,191,83)}} do
		local o=Instance.new('TextLabel');o.Name,o.Text,o.Size='PlanGizmo'..spec[1],spec[2],UDim2.fromOffset(26,26)
		o.AnchorPoint,o.BackgroundColor3,o.TextColor3=Vector2.new(.5,.5),spec[3],Color3.fromRGB(23,34,40)
		o.BorderSizePixel,o.TextSize,o.Font,o.ZIndex,o.Parent=0,20,Enum.Font.SourceSansBold,24,gizmo
		gizmoHandles[spec[1]]=o
	end
	local axisX=Instance.new('Frame');axisX.BackgroundColor3=Color3.fromRGB(218,103,99);axisX.Size=UDim2.fromOffset(128,2);axisX.AnchorPoint=Vector2.new(.5,.5);axisX.BorderSizePixel=0;axisX.ZIndex=22;axisX.Parent=gizmo
	local axisZ=Instance.new('Frame');axisZ.BackgroundColor3=Color3.fromRGB(90,164,220);axisZ.Size=UDim2.fromOffset(2,128);axisZ.AnchorPoint=Vector2.new(.5,.5);axisZ.BorderSizePixel=0;axisZ.ZIndex=22;axisZ.Parent=gizmo
	local status=label(root,'출입구 쪽은 도면 아래입니다. 완성한 배치는 실제 건물에 즉시 적용됩니다.',UDim2.new(0,16,1,-72),UDim2.new(1,-32,0,62))
	local target,p,plan=nil,nil,nil;local scale,ox,oy=1,0,0;local controller={};local globalConnections={}
	local copies=setmetatable({},{__mode='k'})
	local colors={Wall=Color3.fromRGB(225,229,220),Block=Color3.fromRGB(199,207,196),Stairs=Color3.fromRGB(219,173,84),Elevator=Color3.fromRGB(91,176,209)}
	local function point(x,z) return ox+x*scale,oy-z*scale end
	local function frame(parent,x,y,w,h,color,alpha)
		local o=Instance.new('Frame');o.Position,o.Size=UDim2.fromOffset(math.floor(x+.5),math.floor(y+.5)),UDim2.fromOffset(math.max(1,math.floor(w+.5)),math.max(1,math.floor(h+.5)))
		o.BorderSizePixel,o.BackgroundColor3,o.BackgroundTransparency=0,color,alpha or 0;o.Parent=parent;return o
	end
	local function clear(parent) for _,o in parent:GetChildren() do o:Destroy() end end
	local function clearDrag()
		local old=drag;drag=nil
		if old and old.Watch then old.Watch.Disconnect() end
		return old
	end
	local function entry(id) if plan then for _,e in plan.Items do if e.Id==id then return e end end end;return nil end
	local function selectedWall()
		local e=entry(selected);return if tool=='Select' and e and e.Kind=='Wall' then e else nil
	end
	local function thicknessText(n) return string.format('%.5g',n) end
	local function canUndoCopy()
		local record=target and copies[target]
		return record and p and record.After==p.PlanJSON
	end
	local function showGizmo(e,preview)
		gizmo.Visible=e~=nil and tool=='Select';table.clear(handlePositions)
		if not e then pivotX.Text,pivotZ.Text,pivotAngle.Text='—','—','—';return end
		local x,z=B.center(e);local px,py=point(x,z);local angle=B.angle(e)
		local function position(o,a,b) o.Position=UDim2.fromOffset(math.floor(a+.5),math.floor(b+.5)) end
		position(ring,px,py);position(axisX,px,py);position(axisZ,px,py)
		-- Keep the rotation target between the axes so it cannot cover an arrow.
		local positions={X={px+64,py},XNegative={px-64,py},Z={px,py-64},ZNegative={px,py+64},Move={px,py},Rotate={px+37,py-37}}
		for key,pixels in positions do
			position(gizmoHandles[key],pixels[1],pixels[2])
			handlePositions[key]={math.floor(pixels[1]+.5),math.floor(pixels[2]+.5)}
		end
		if not preview then pivotX.Text,pivotZ.Text,pivotAngle.Text=string.format('%.3f',x),string.format('%.3f',z),string.format('%.1f',angle) end
	end
	local function line(parent,x0,z0,x1,z1,width,color,alpha)
		local x,y=point(x0,z0);local a,b=point(x1,z1);local dx,dy=a-x,b-y
		local o=frame(parent,(x+a)*.5,(y+b)*.5,math.sqrt(dx*dx+dy*dy),width*scale,color,alpha)
		o.AnchorPoint=Vector2.new(.5,.5);o.Rotation=math.deg(math.atan2(dy,dx));return o
	end
	local function rectangle(parent,e,color,alpha)
		local bounds=B.bounds(e);local x,y=point(bounds.X0,bounds.Z1)
		return frame(parent,x,y,(bounds.X1-bounds.X0)*scale,(bounds.Z1-bounds.Z0)*scale,color,alpha)
	end
	local function drawItem(parent,e,ghost)
		local color=if e.Id==selected then Color3.fromRGB(148,226,158) else colors[e.Kind]
		if e.Kind=='Wall' then
			local a,b=B.doorSpan(e);local alpha=if ghost then .65 else 0
			if not a then line(parent,e.X,e.Z,e.X2,e.Z2,e.Thickness,color,alpha)
			else
				local length=B.wallLength(e)
				local dx,dz=(e.X2-e.X)/length,(e.Z2-e.Z)/length
				local ax,az,bx,bz=e.X+a*dx,e.Z+a*dz,e.X+b*dx,e.Z+b*dz
				line(parent,e.X,e.Z,ax,az,e.Thickness,color,alpha)
				line(parent,bx,bz,e.X2,e.Z2,e.Thickness,color,alpha)
				local doorColor=Color3.fromRGB(237,189,114)
				line(parent,ax,az,bx,bz,.045,doorColor,if ghost then .75 else .35)
				line(parent,ax,az,ax+dz*.85,az-dx*.85,.07,doorColor,alpha)
			end
		else
			local o=rectangle(parent,e,color,if ghost then (if e.Id==selected then .47 else .8) else .12)
			if e.Kind=='Stairs' or e.Kind=='Elevator' then
				local text=if e.Kind=='Elevator' then '엘리베이터\n전 층 연결'
					elseif e.Floor<floor then e.Floor..'층에서 올라오는 계단'
					else '계단 ↑'..(e.Floor+1)..'층\n'..e.Rotation..'°'
				label(o,text,UDim2.fromScale(0,0),UDim2.fromScale(1,1)).TextColor3=Color3.fromRGB(25,38,42)
			end
		end
	end
	local function render()
		clear(drawing);clear(hover)
		local undo=canUndoCopy()==true
		undoCopy.Active,undoCopy.AutoButtonColor,undoCopy.TextTransparency=undo,undo,if undo then 0 else .48
		local wall=selectedWall()
		thickness.Text=thicknessText(if wall then wall.Thickness else wallThickness)
		if not p then showGizmo(nil);return end
		local size=canvas.AbsoluteSize;scale=math.max(1,math.min((size.X-70)/p.Width,(size.Y-70)/p.Depth));ox,oy=size.X*.5,size.Y*.5
		local x,y=point(-p.Width*.5,p.Depth*.5)
		frame(drawing,x,y,p.Width*scale,p.Depth*scale,Color3.fromRGB(62,75,85))
		for gx=-math.floor(p.Width*2)*.25,p.Width*.5,.25 do line(drawing,gx,-p.Depth*.5,gx,p.Depth*.5,.012,Color3.fromRGB(78,93,104),.45) end
		for gz=-math.floor(p.Depth*2)*.25,p.Depth*.5,.25 do line(drawing,-p.Width*.5,gz,p.Width*.5,gz,.012,Color3.fromRGB(78,93,104),.45) end
		local edge=Color3.fromRGB(173,186,190)
		for _,sx in {-1,1} do line(drawing,sx*p.Width*.5,-p.Depth*.5,sx*p.Width*.5,p.Depth*.5,.20,edge) end
		for _,sz in {-1,1} do line(drawing,-p.Width*.5,sz*p.Depth*.5,p.Width*.5,sz*p.Depth*.5,.20,edge) end
		if floor==1 then
			local bays=math.max(2,math.floor(p.Width/2.7));local pitch=p.Width/bays;local door=(math.ceil(bays*.65)-(bays+1)*.5)*pitch
			local geometry=target:FindFirstChild('Geometry')
			if geometry then door=geometry:GetAttribute('PlanEntryX') or door end
			line(drawing,door-.55,-p.Depth*.5,door+.55,-p.Depth*.5,.23,Color3.fromRGB(126,213,157))
		end
		if p.PlanJSON=='' then
			line(drawing,-p.Width*.5+.28,p.Depth*.24,p.Width*.5-.28,p.Depth*.24,.12,Color3.fromRGB(119,133,140),.45)
			line(drawing,p.Width*.18,-p.Depth*.18,p.Width*.18,p.Depth*.22,.12,Color3.fromRGB(119,133,140),.45)
		end
		for _,e in plan.Items do if e.Kind=='Stairs' and e.Floor+1==floor then drawItem(drawing,e,true) end end
		for _,e in plan.Items do if B.visible(e,floor) then drawItem(drawing,e,drag~=nil and e.Id==selected) end end
		local _,bottom=point(0,-p.Depth*.5)
		label(drawing,'출입구 쪽 · '..p.Width..' × '..p.Depth..' m',UDim2.fromOffset(0,math.floor(bottom+7)),UDim2.new(1,0,0,23))
		floorBox.Text=tostring(floor);title.Text=(target and target.Name or '')..' · '..floor..' / '..p.Floors..'층'
		for key,b in tools do b.BackgroundColor3=if key==tool then Color3.fromRGB(83,131,109) else Color3.fromRGB(56,72,81) end
		showGizmo(entry(selected))
	end
	local function rawMouse()
		local mouse=widget:GetRelativeMousePosition()-canvas.AbsolutePosition
		return (mouse.X-ox)/scale,(oy-mouse.Y)/scale
	end
	local function atMouse()
		local x,z=rawMouse();return B.snap(x),B.snap(z)
	end
	local function clone()
		local out={Version=1,Items={}};for _,e in plan.Items do table.insert(out.Items,table.clone(e)) end;return out
	end
	local function commit(candidate,id,selectPlaced,reason)
		if not target or bridge.Get()~=target or not target.Parent then status.Text='같은 건물을 선택한 상태에서 편집하세요.';return false end
		local owner,previous=target,p.PlanJSON
		local ok,result=pcall(function()
			local encoded=if type(candidate)=='string' then candidate else B.encode(candidate,p)
			local decoded=B.decode(encoded,p)
			local success,err=bridge.Apply(owner,encoded);assert(success,err or '도면 적용 실패')
			return decoded
		end)
		if ok then
			plan=result;p=P.read(target);selected=id
			if reason=='copy' then copies[owner]={Before=previous,After=p.PlanJSON}
			elseif reason=='restore' then copies[owner]=nil end
			if selectPlaced then tool='Select' end
			status.Text=if selectPlaced then '배치 완료 · 피봇이나 계단을 바로 끌어 옮길 수 있어요.' else '건물에 적용 완료 · Ctrl+Z로 되돌릴 수 있어요.'
		else status.Text=tostring(result):gsub('^.-:%d+:%s*','') end
		pending=nil;clearDrag();render();return ok
	end
	local function newId()
		local id=0;local used={}
		for _,e in plan.Items do id=math.max(id,e.Id);used[e.Id]=true end
		if id<1000000 then return id+1 end
		id=1;while used[id] do id+=1 end;return id
	end
	local function erase(id)
		local candidate=clone();for i=#candidate.Items,1,-1 do if candidate.Items[i].Id==id then table.remove(candidate.Items,i) end end;commit(candidate,nil)
	end
	local function replace(e)
		local candidate=clone()
		for i,item in candidate.Items do if item.Id==e.Id then candidate.Items[i]=e;break end end
		return commit(candidate,e.Id)
	end
	local function scrubValue(g)
		local dx=(widget:GetRelativeMousePosition().X-g.StartPixel)/g.PixelsPerStep
		local steps=math.sign(dx)*math.floor(math.abs(dx))
		local value=g.Value+g.Step*steps
		if g.Axis=='Thickness' then value=math.clamp(value,B.WallMin,B.WallMax) end
		return value
	end
	local function transformed()
		if not drag then return nil end
		if drag.ScrubField then
			local g=drag;local value=scrubValue(g);local original=g.Original
			if not original then return nil,value end
			local delta=value-g.Value
			if g.Axis=='Thickness' then local e=table.clone(original);e.Thickness=value;return e,value end
			return B.transform(original,if g.Axis=='X' then delta else 0,if g.Axis=='Z' then delta else 0,if g.Axis=='Rotate' then delta else 0),value
		end
		local x,z=rawMouse();local dx,dz=B.snap(x-drag.X),B.snap(z-drag.Z);local angle=0
		if drag.Axis=='Rotate' then
			local cx,cz=B.center(drag.Original)
			if ((x-cx)^2+(z-cz)^2)*scale^2<64 then return drag.Preview or drag.Original end
			local delta=math.atan2(-(z-cz),x-cx)-drag.StartAngle;delta=math.atan2(math.sin(delta),math.cos(delta))
			local step=if drag.Original.Kind=='Wall' then 15 else 90
			angle=math.floor(math.deg(delta)/step+.5)*step;dx,dz=0,0
		elseif drag.Axis=='X' or drag.Axis=='XNegative' then dz=0
		elseif drag.Axis=='Z' or drag.Axis=='ZNegative' then dx=0 end
		return B.transform(drag.Original,dx,dz,angle)
	end
	local function drawDrag()
		if not drag then return end
		clear(hover);local preview,value=transformed()
		if drag.ScrubField then
			drag.ScrubField.Text=if drag.Axis=='Thickness' then thicknessText(value)
				elseif drag.Axis=='Rotate' then string.format('%.1f',value%360) else string.format('%.3f',value)
			status.Text='↔ 드래그로 값 조절 · 놓으면 적용 / Esc 취소'
		end
		if not preview then return end
		drag.Preview=preview;drawItem(hover,preview,false);showGizmo(preview,true)
		if drag.ScrubField then return end
		local x,z=B.center(preview);status.Text=string.format('X %.2f m · Z %.2f m · 각도 %.0f° · 놓으면 적용 / Esc 취소',x,z,B.angle(preview))
	end
	local function hitGizmo()
		if not gizmo.Visible then return nil end
		local mouse=widget:GetRelativeMousePosition()-canvas.AbsolutePosition
		for key,pos in handlePositions do if math.abs(mouse.X-pos[1])<=13 and math.abs(mouse.Y-pos[2])<=13 then return key end end
		return nil
	end
	local function cancelGesture()
		pending=nil;clearDrag();render()
		status.Text='진행 중인 편집을 취소했습니다.'
	end
	local function finishDrag(commitEdit)
		if not drag then return end
		if not commitEdit or not widget.Enabled or Run:IsRunning() or drag.Owner~=target or drag.Floor~=floor then cancelGesture();return end
		local result,value=transformed();local old=clearDrag()
		if old.ScrubField then
			if math.abs(value-old.Value)<.00001 then render();return end
			if result then replace(result)
			else wallThickness=value;render();status.Text='새 벽 두께: '..thicknessText(value)..' m' end
			return
		end
		if not result then render();return end
		local cx,cz=B.center(old.Original);local x,z=B.center(result)
		if math.abs(x-cx)<.00001 and math.abs(z-cz)<.00001 and math.abs(B.angle(result)-B.angle(old.Original))<.00001 then render();return end
		replace(result)
	end
	local function watchDrag(gesture,track,input)
		clearDrag();drag=gesture
		gesture.Watch=Pointer.watch(track,input,function(ok) if drag==gesture then finishDrag(ok) end end)
		render()
	end
	local function beginDrag(axis,input)
		local e=entry(selected);if not e then return end
		local x,z=rawMouse();local cx,cz=B.center(e)
		pending=nil
		watchDrag({Axis=axis,X=x,Z=z,Original=table.clone(e),StartAngle=math.atan2(-(z-cz),x-cx),Owner=target,Floor=floor},surface,input)
		status.Text=if axis=='Rotate' then '회전 링을 끌어 방향 조절 · 놓으면 적용 · Esc 취소' else '피봇을 끌어 이동 · 놓으면 적용 · Esc 취소'
	end
	local function bindScrub(track,box,axis)
		track.InputBegan:Connect(function(input)
			if not widget.Enabled or not p or Run:IsRunning() then return end
			if input.KeyCode==Enum.KeyCode.Escape then cancelGesture();return end
			if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
			local e=if axis=='Thickness' then selectedWall() else (if tool=='Select' then entry(selected) else nil)
			if not e and axis~='Thickness' then status.Text='값을 조절할 부품을 먼저 선택하세요.';return end
			local value,step,pixels
			if axis=='Thickness' then value=(if e then e.Thickness else wallThickness);step,pixels=.01,5
			elseif axis=='Rotate' then value=B.angle(e);step,pixels=(if e.Kind=='Wall' then 15 else 90),12
			else local x,z=B.center(e);value=(if axis=='X' then x else z);step,pixels=B.Grid,8 end
			watchDrag({Axis=axis,ScrubField=box,Original=e and table.clone(e),Value=value,Step=step,PixelsPerStep=pixels,
				StartPixel=widget:GetRelativeMousePosition().X,Owner=target,Floor=floor},track,input)
		end)
	end
	bindScrub(thicknessLabel,thickness,'Thickness');bindScrub(labelX,pivotX,'X');bindScrub(labelZ,pivotZ,'Z');bindScrub(labelAngle,pivotAngle,'Rotate')
	local function readThickness()
		local value=tonumber(thickness.Text)
		if not value or not (value>=B.WallMin and value<=B.WallMax) then status.Text='벽 두께는 0.08~0.4m로 입력하세요.';return nil end
		return value
	end
	local function applyCoordinates()
		if drag then return end
		local wall=selectedWall()
		local width=if wall then readThickness() else nil
		if wall and not width then return end
		local e=entry(selected);if not e or not p or Run:IsRunning() then return end
		local x,z,a=tonumber(pivotX.Text),tonumber(pivotZ.Text),tonumber(pivotAngle.Text)
		if not x or not z or not a or x~=x or z~=z or a~=a or math.abs(x)==math.huge or math.abs(z)==math.huge or math.abs(a)==math.huge then status.Text='X·Z·각도를 올바른 숫자로 입력하세요.';return end
		local cx,cz=B.center(e);local changed=B.transform(e,x-cx,z-cz,a-B.angle(e))
		if width then changed.Thickness=width end
		replace(changed)
	end
	applyPivot.MouseButton1Click:Connect(applyCoordinates)
	for _,box in {pivotX,pivotZ,pivotAngle} do box.FocusLost:Connect(function(enter) if enter then applyCoordinates() end end) end
	thickness.FocusLost:Connect(function(enter)
		if drag or Run:IsRunning() then return end
		local wall=selectedWall()
		if wall then
			if enter then
				local value=readThickness()
				if value and value~=wall.Thickness then local e=table.clone(wall);e.Thickness=value;replace(e) end
			end
		else local value=readThickness();if value then wallThickness=value end end
	end)
	for key,b in tools do b.MouseButton1Click:Connect(function()
		tool=key;pending=nil;clearDrag();render()
		if key=='Door' then status.Text='벽 선을 클릭해 문을 넣거나 옮깁니다. 기존 문을 다시 클릭하면 지웁니다.' end
	end) end
	local function changeFloor(value)
		if not p then return end
		local newFloor=math.clamp(math.floor(value),1,p.Floors)
		if newFloor==floor then floorBox.Text=tostring(floor);return end
		floor=newFloor;pending,selected=nil,nil;clearDrag();render()
	end
	prev.MouseButton1Click:Connect(function() changeFloor(floor-1) end);nextFloor.MouseButton1Click:Connect(function() changeFloor(floor+1) end)
	floorBox.FocusLost:Connect(function() changeFloor(tonumber(floorBox.Text) or floor) end)
	remove.MouseButton1Click:Connect(function() if selected then erase(selected) end end)
	rotate.MouseButton1Click:Connect(function()
		if not p then return end
		if not selected then rotation=(rotation+90)%360;status.Text='새 계단·블록 방향: '..rotation..'°';return end
		local candidate=clone()
		for i,e in candidate.Items do if e.Id==selected then candidate.Items[i]=B.transform(e,0,0,90) end end
		commit(candidate,selected)
	end)
	local function copyFloors(all)
		if not p or Run:IsRunning() or drag then return end
		local source=floor
		local ok,candidate=pcall(B.copyFloors,plan,p,source,all)
		if not ok then status.Text=tostring(candidate):gsub('^.-:%d+:%s*','');return end
		if commit(candidate,nil,false,'copy') then
			if not all then changeFloor(source+1) end
			status.Text=if all then source..'층을 기준으로 다른 층을 덮어썼어요 · 복사 되돌리기로 복원'
				else '다음 층에 복사했어요 · 복사 되돌리기로 복원'
		end
	end
	copy.MouseButton1Click:Connect(function() copyFloors(false) end)
	copyAll.MouseButton1Click:Connect(function() copyFloors(true) end)
	undoCopy.MouseButton1Click:Connect(function()
		if drag or Run:IsRunning() or not canUndoCopy() then return end
		if commit(copies[target].Before,nil,false,'restore') then status.Text='복사하기 전 층별 배치로 복원했어요.' end
	end)
	surface.InputBegan:Connect(function(input)
		if not widget.Enabled or not p or Run:IsRunning() then return end
		if input.KeyCode==Enum.KeyCode.Escape then cancelGesture();return end
		if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
		local rx,rz=rawMouse()
		if tool=='Select' then
			local axis=hitGizmo()
			if axis then beginDrag(axis,input);return end
			local hit=B.pick(plan,floor,rx,rz,nil,math.max(.18,7/scale)) or B.pickArrival(plan,floor,rx,rz)
			selected=hit and hit.Id
			if hit then beginDrag('Move',input) else render() end
			return
		end
		local x,z=B.snap(rx),B.snap(rz);if math.abs(x)>p.Width*.5 or math.abs(z)>p.Depth*.5 then return end
		if tool=='Door' then
			local wall=B.pick(plan,floor,rx,rz,'Wall',math.max(.18,8/scale))
			if not wall then status.Text='문을 넣을 벽 선을 클릭하세요.';return end
			local length=B.wallLength(wall);local t=B.wallProjection(wall,rx,rz)
			local at=t*length;local a,b=B.doorSpan(wall)
			local newAt=nil
			if not a or at<a or at>b then
				local margin=B.DoorWidth*.5+B.DoorMargin
				if length<2*margin then status.Text='문을 넣으려면 1.44m 이상의 벽이 필요합니다.';return end
				newAt=math.clamp(B.snap(at),margin,length-margin)/length
			end
			local candidate=clone()
			for _,e in candidate.Items do if e.Id==wall.Id then e.DoorAt=newAt end end
			commit(candidate,wall.Id);return
		end
		local hit=B.pick(plan,floor,rx,rz,nil,math.max(.18,7/scale))
		if tool=='Erase' then if hit then erase(hit.Id) end;return end
		if tool=='Wall' or tool=='Block' then
			if not pending then pending={X=x,Z=z};status.Text='끝점을 한 번 더 클릭하세요. Esc로 취소합니다.';return end
			local candidate=clone();local id=newId();local entry={Id=id,Kind=tool,Floor=floor,X=pending.X,Z=pending.Z}
			if tool=='Wall' then local width=readThickness();if not width then return end;wallThickness=width;entry.X2,entry.Z2,entry.Thickness=x,z,width
			else entry.X,entry.Z=(pending.X+x)*.5,(pending.Z+z)*.5;entry.Width,entry.Depth=math.abs(x-pending.X),math.abs(z-pending.Z);entry.Rotation=0 end
			table.insert(candidate.Items,entry);commit(candidate,id)
		else
			local candidate=clone();local id=newId();table.insert(candidate.Items,{Id=id,Kind=tool,Floor=floor,X=x,Z=z,Rotation=rotation});commit(candidate,id,tool=='Stairs')
		end
	end)
	local elapsed=0
	table.insert(globalConnections,Run.Heartbeat:Connect(function(dt)
		elapsed+=dt;if elapsed<.04 then return end;elapsed=0
		if not widget.Enabled or not p then return end
		if drag then
			if Run:IsRunning() then cancelGesture()
			elseif not drag.Watch.Poll() then drawDrag() end
			return
		end
		if not pending then return end
		clear(hover);local x,z=atMouse()
		if tool=='Wall' then line(hover,pending.X,pending.Z,x,z,tonumber(thickness.Text) or wallThickness,Color3.fromRGB(147,219,163),.2)
		elseif tool=='Block' then rectangle(hover,{Kind='Block',X=(pending.X+x)*.5,Z=(pending.Z+z)*.5,Width=math.abs(x-pending.X),Depth=math.abs(z-pending.Z),Rotation=0},Color3.fromRGB(147,219,163),.3) end
	end))
	canvas:GetPropertyChangedSignal('AbsoluteSize'):Connect(render)
	function controller.Refresh()
		if not widget.Enabled then return end
		local building=bridge.Get();if not building or not building.Parent then target,p,plan=nil,nil,nil;clearDrag();pending,selected=nil,nil;render();title.Text='건물을 하나 선택하세요.';return end
		local config=P.read(building);local ok,value=pcall(B.decode,config.PlanJSON,config)
		if not ok then status.Text=tostring(value);return end
		if target~=building then selected=nil end
		target,p,plan=building,config,value;floor=math.clamp(floor,1,p.Floors);pending=nil;clearDrag();render()
	end
	function controller.Open() widget.Enabled=true;controller.Refresh() end
	function controller.Destroy() clearDrag();for _,connection in globalConnections do connection:Disconnect() end;widget:Destroy() end
	widget.WindowFocusReleased:Connect(function() if drag then cancelGesture() end end)
	widget:BindToClose(function() pending=nil;clearDrag();widget.Enabled=false end)
	return controller
end
