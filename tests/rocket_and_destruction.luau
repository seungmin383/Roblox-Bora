local r,fs=require('@lune/roblox'),require('@lune/fs')
local V,C,I=r.Vector3,r.CFrame,r.Instance
local F=require('../src/RocketFlight')(V)
local start=V.new(0,4,0)
assert(F.aim(start,V.new(0,4,-50))==V.new(0,0,-1))
assert(not F.aim(start,start) and not F.aim(start,'oops') and not F.aim(start,V.new(math.huge,0,0)))
for _,dt in {1/30,1/60,1/144,.5} do
	local flight={Position=start,Direction=V.new(0,0,-1),Age=0}
	local hits=0
	local function cast(from,delta)
		if from.Z>=-29 and from.Z+delta.Z<=-29 then hits+=1;return {Position=V.new(0,4,-29)} end
	end
	for _=1,math.ceil(6/dt) do
		local hit,done=F.advance(flight,dt,cast)
		if done then assert(hit and hit.Position.Z==-29);break end
	end
	assert(hits==1 and flight.Position.Z==-29,'Rocket tunneled through wall')
end
local miss={Position=start,Direction=-V.zAxis,Age=0}
local hit,done=F.advance(miss,8,function() return nil end)
assert(done and not hit and miss.Age==F.Lifetime and math.abs(miss.Position.Z+F.Speed*F.Lifetime)<.01)
local launcher=I.new('Tool');local handle=require('../src/RocketLauncherFactory')(r).model(launcher,C.new(),false)
assert(handle.Name=='Handle' and handle.Muzzle.Position.Z< -3 and not handle.CanCollide)
for _,p in launcher:GetChildren() do if p~=handle then assert(p:FindFirstChildOfClass('WeldConstraint').Part0==handle) end end
local place=r.deserializePlace(fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*',''))
local world=place:GetService('Workspace')
local town=world.BoraNeighborhood_01
local rubble=I.new('Folder');local calls,scheduled,levels={}, {}, {}
local directHits=0
local hasRoom=true
local D=require('../src/BuildingDestruction')(r,{
	Release=function(p,velocity)
		assert(velocity.Magnitude>0);p.Anchored=false;p.Parent=rubble;table.insert(calls,p)
	end,
	HasRoom=function() return hasRoom end,
	BeforePartition=function() directHits+=1 end,
	Schedule=function(delay,fn) table.insert(scheduled,{Delay=delay,Fn=fn}) end,
	Collapse=function(_,floor,count) assert(count>0);table.insert(levels,floor) end,
})
local villa=town.Buildings.BoraVilla
local s=assert(D.register(villa));assert(s.Support[1] and s.Support[1].Total>0)
local function strike(building,wall)
	local cf,size=wall.CFrame,wall.Size
	local surface,normal
	if size.X<size.Z then surface,normal=cf.Position+cf.RightVector*(size.X*.5),cf.RightVector
	else surface,normal=cf.Position+cf.LookVector*(size.Z*.5),cf.LookVector end
	local before,released=directHits,#calls
	if building then assert(D.blast(building,surface,wall,surface+normal*1.8)==1)
	else assert(D.hitStandalone(wall,surface,surface+normal*1.8)==1) end
	assert(directHits==before+1 and #calls>released,'A direct shot did not release wall fragments')
end
local doorway=villa.Geometry.FloorPlanInterior.PlanWall_4
local header,jamb=doorway.DoorHeader,doorway:FindFirstChild('DoorJamb')
local originalSupport=s.Support[1].Gone
strike(villa,doorway.WallStart)
assert(header.Parent==doorway and jamb.Parent==doorway and s.Support[1].Gone==originalSupport and #scheduled==0)
local remnant=doorway.WallStart_Sections:FindFirstChild('WallRemainder')
assert(remnant,'Impact removed the whole long wall');strike(villa,remnant)
local added=world:FindFirstChild('BoraBuildings')
if added then
	for _,building in added:GetChildren() do
		local geo=building:FindFirstChild('Geometry')
		local interior=geo and geo:FindFirstChild('FloorPlanInterior')
		if interior then
			local nearbyFloor=geo.Floor_1.FloorSlab or geo.Floor_1:FindFirstChild('FloorSlabTile')
			for _,name in {'PlanWall_5','PlanBlock_6','PlanBlock_7'} do
				local part=interior:FindFirstChild(name);if part and part:IsA('Part') then strike(building,part) end
			end
			if nearbyFloor then assert(nearbyFloor.Parent==geo.Floor_1) end
		end
	end
end
local function manual(parent,name,frame)
	local wall=I.new('Part')
	wall.Name,wall.Size,wall.CFrame,wall.Anchored,wall.Parent=name,V.new(.65,8,14),frame,true,parent
	return wall
end
-- A hand-placed cell added after the registry was populated still breaks.
strike(villa,manual(villa,'Part',s.Base*C.new(0,4,0)))
local stand=manual(world,'테스트 벽',C.new(0,4,10))
strike(nil,stand)
assert(world:FindFirstChild('테스트 벽_Sections'))
local market=town.Buildings.BoraMarket
local hitMarket=market:Clone();hitMarket.Parent=world
local hitMarketState=assert(D.register(hitMarket))
local backing
for _,attachment in hitMarketState.Attachments do
	if attachment.Cell.Record.Name=='WindowGlass' then
		for host in attachment.Links do
			if host.Record.Name=='UpperMasonry' and D.distance(host.Frame,host.Size,attachment.Cell.Frame.Position)<2 then
				backing=host;break
			end
		end
	end
	if backing then break end
end
assert(backing,'No facade target found')
assert(D.blast(hitMarket,backing.Frame.Position,backing.Record.Source)>0)
assert(D.blast(hitMarket,backing.Frame.Position,nil)>0)
assert(backing.Gone,'Rockets did not open the market facade')
local droppedWindow,intactAfterHit=false,false
for _,cell in hitMarketState.Cells do
	if cell.Record.Name=='WindowGlass' then
		if cell.Gone then droppedWindow=true else intactAfterHit=true end
	end
end
assert(droppedWindow and intactAfterHit,'Local rocket hits should only breach part of the market facade')
assert(#scheduled==0,'Local facade blast triggered global collapse')
hitMarket:Destroy()
local marketState=assert(D.register(market))
assert(marketState.Support[1].Total>0 and marketState.Support[2].Total>0)
local pane,trim
for _,attachment in marketState.Attachments do
	if attachment.Cell.Record.Name=='WindowGlass' then pane=attachment;break end
end
assert(pane,'Market glass has no backing')
for _,attachment in marketState.Attachments do
	if attachment.Links==pane.Links and attachment.Cell.Record.Name=='WindowFrame' then trim=attachment;break end
end
assert(trim,'Market glass and frame must follow the same opening')
local far=marketState.Base:PointToWorldSpace(V.new(0,0,500))
-- Remove the backing only. The distant blast cannot directly hit any trim.
for host in pane.Links do host.Gone=true end
assert(D.blast(market,far,nil)>0 and pane.Cell.Gone and trim.Cell.Gone)
assert(not pane.Cell.Part.Anchored and not trim.Cell.Part.Anchored)
local intactWindow=false
for _,attachment in marketState.Attachments do
	if attachment.Cell.Record.Name=='WindowGlass' and not attachment.Cell.Gone then intactWindow=true;break end
end
assert(intactWindow,'A supported window fell with a different opening')
for _,cell in marketState.Cells do
	if cell.Record.Name=='UpperMasonry' then cell.Gone=true end
end
assert(D.blast(market,far,nil)>0)
local roofParts={RoofCap=false,RoofParapet=false,AirConditioner=false,RoofAccess=false,AccessCap=false,CondenserSlat=false}
for _,cell in marketState.Cells do
	local name=cell.Record.Name
	if roofParts[name]~=nil or name=='WindowGlass' or name=='WindowFrame' then
		assert(cell.Gone,'Unsupported '..name..' stayed anchored')
		if roofParts[name]~=nil then roofParts[name]=true end
	end
end
for name,found in roofParts do assert(found,'Missing fixture '..name) end
for _,cell in marketState.Cells do
	if cell.Record.Name=='GroundCeiling' then cell.Gone=true end
end
local beforeBudget=#calls
hasRoom=false
D.blast(market,far,nil)
hasRoom=true
assert(#calls==beforeBudget,'Detached parts bypassed the fragment budget')
for _,cell in marketState.Cells do
	if cell.Record.Name=='FloorBand' then assert(cell.Gone,'A band lost its slab and stayed anchored') end
end
local candidates={}
for _,cell in s.Cells do if cell.Weight and cell.Floor==1 then table.insert(candidates,cell) end end
local first=candidates[math.floor(#candidates*.5)]
local localLoss=D.blast(villa,first.Frame.Position,first.Record.Source)
assert(localLoss>0 and #calls>0 and #scheduled==0,'A single local breach should not collapse the upper floors')
local live=false
for _,cell in candidates do if not cell.Gone then live=true;break end end
assert(live and villa:GetAttribute('BoraCollapseFromFloor')==nil)
for _,cell in candidates do
	if not cell.Gone then D.blast(villa,cell.Frame.Position,nil) end
	if #scheduled>0 then break end
end
assert(villa:GetAttribute('BoraCollapseFromFloor')==2 and #scheduled==s.Floors)
assert(s.Support[1].Gone/s.Support[1].Total>=.52)
assert(s.Geometry:FindFirstChild('VillaHallLighting') and town.Buildings:FindFirstChild('BoraVilla')==villa)
table.sort(scheduled,function(a,b) return a.Delay<b.Delay end)
local earlier=#calls
for _,stage in scheduled do stage.Fn() end
assert(#levels>=2 and levels[1]==2 and levels[2]==3 and #calls>earlier)
assert(villa:FindFirstChild('BuildingOrigin') and villa.Geometry:FindFirstChild('GroundFloorSlab'))
for _,p in rubble:GetChildren() do assert(not p.Anchored) end
print('PASS: rocket flight, partition hits, local breaches, market window and roof detachment, floor bands and phased collapse.')
