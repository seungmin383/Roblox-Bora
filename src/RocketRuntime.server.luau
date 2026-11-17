-- [BoraRocketRuntime] Server-owned launcher, swept flight and building physics.
local Players=game:GetService('Players')
local Replicated=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Debris=game:GetService('Debris')
local api={Instance=Instance,Vector3=Vector3,CFrame=CFrame,Enum=Enum,Color3=Color3}
local Fracture=require(script.BuildingFracture)(api)
local Model=require(script.RocketLauncherFactory)(api)
local Flight=require(script.RocketFlight)(Vector3)

local function folder(parent,name)
	local object=Instance.new('Folder');object.Name,object.Parent=name,parent;return object
end
local function collider(parent,name,size,cf,color,material,combine)
	local p=Instance.new('Part');p.Name,p.Size,p.CFrame,p.Color,p.Material=name,size,cf,color,material
	p.Anchored,p.CanCollide,p.CanTouch=true,combine==true,false;p.CanQuery=true
	p.TopSurface,p.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
	p.Parent=parent;return p
end
local runtime=folder(workspace,'BoraRocketPlay')
local rockets=folder(runtime,'Projectiles')
local rubble=folder(runtime,'Rubble')
local remote=Replicated:FindFirstChild('BoraRocketFire')
if remote then assert(remote:IsA('RemoteEvent') and remote:GetAttribute('BoraOwned'),'Rocket remote name collision')
else
	remote=Instance.new('RemoteEvent');remote.Name='BoraRocketFire';remote:SetAttribute('BoraOwned',true);remote.Parent=Replicated
end

local function visual(position,radius)
	local blast=Instance.new('Explosion');blast.Name='RocketBlast';blast.Position=position
	blast.BlastRadius,blast.BlastPressure,blast.DestroyJointRadiusPercent=radius,0,0
	blast.ExplosionType=Enum.ExplosionType.NoCraters;blast.Parent=runtime
	Debris:AddItem(blast,2)
end
local function kick(part,velocity,spin)
	if part:CanSetNetworkOwnership() then part:SetNetworkOwner(nil) end
	part:ApplyImpulse(velocity*part.AssemblyMass)
	part:ApplyAngularImpulse(spin*part.AssemblyMass)
end
local activeRubble=0
local rubbleQueue={};local dropBudget=0
local function trimRubble(limit)
	while activeRubble>limit and #rubbleQueue>0 do
		local record=table.remove(rubbleQueue,1)
		if record.Live then record.Live=false;activeRubble-=1;record.Part:Destroy() end
	end
end
local function prepareDrop()
	-- Reserve visible rubble for each floor, even after several prior shots.
	dropBudget=30
	trimRubble(145-dropBudget)
end
local damage
damage=require(script.BuildingDestruction)(api,{
	BeforeDrop=prepareDrop,
	BeforePartition=function() trimRubble(102) end,
	HasRoom=function(collapse) return activeRubble<(if collapse then 145 else 110) and (not collapse or dropBudget>0) end,
	Release=function(part,velocity,spin,collapse)
		if activeRubble>=(if collapse then 145 else 110) or (collapse and dropBudget<=0) then part:Destroy();return end
		if collapse then dropBudget-=1 end
		activeRubble+=1
		local record={Part=part,Live=true};table.insert(rubbleQueue,record)
		while #rubbleQueue>0 and not rubbleQueue[1].Live do table.remove(rubbleQueue,1) end
		part.Destroying:Once(function() if record.Live then record.Live=false;activeRubble-=1 end end)
		part.Parent=rubble;part.CanTouch=false;part.Anchored=false
		kick(part,velocity,spin)
		Debris:AddItem(part,10)
	end,
	Schedule=function(delay,fn) task.delay(delay,fn) end,
	Collapse=function(building,floor)
		print(('[BoraRocket] %s 지지 붕괴 · %d층 낙하'):format(building.Name,floor))
	end,
})
local function buildingOf(instance)
	local at=instance
	while at and at~=workspace do
		if at:IsA('Model') and at:GetAttribute('AssetKind')=='BoraBuilding' then return at end
		at=at.Parent
	end
	return nil
end
local practice=nil
local function detonate(hit,origin)
	local pos=hit.Position;visual(pos,damage.BlastRadius)
	local direct=buildingOf(hit.Instance)
	local onPractice=practice and practice.Parent and (practice==hit.Instance or damage.distance(practice.CFrame,practice.Size,pos)<3.5)
	if onPractice then
		local wall=practice;practice=nil
		Fracture.breakWall(wall,origin,rubble,{Kick=kick,Expire=function(part,time) Debris:AddItem(part,time) end})
	end
	if not direct and not onPractice then damage.hitStandalone(hit.Instance,pos,origin) end
	local query=OverlapParams.new();query.FilterType=Enum.RaycastFilterType.Exclude
	query.FilterDescendantsInstances={runtime};query.MaxParts=300
	local all={}
	if direct then all[direct]=true end
	for _,part in workspace:GetPartBoundsInRadius(pos,damage.BlastRadius,query) do
		local candidate=buildingOf(part);if candidate then all[candidate]=true end
	end
	for building in all do damage.blast(building,pos,hit.Instance,origin) end
end

local spawn=workspace:FindFirstChild('CenterSpawn')
if not spawn or not spawn:IsA('BasePart') then spawn=workspace:FindFirstChildWhichIsA('SpawnLocation',true) end
local spawnCf=if spawn then spawn.CFrame else CFrame.new(0,1,0)
local down=RaycastParams.new();down.FilterType=Enum.RaycastFilterType.Exclude;down.RespectCanCollide=true
down.FilterDescendantsInstances={runtime}
local function ground(point,depth)
	local hit=workspace:Raycast(point+Vector3.yAxis*6,-Vector3.yAxis*(depth or 22),down)
	if hit and hit.Normal.Y>=.94 then return hit.Position.Y end
	return nil
end
if Run:IsStudio() then
	-- Shootable practice wall on open ground ahead of the spawn; no E prompt.
	local bounds=OverlapParams.new();bounds.FilterType=Enum.RaycastFilterType.Exclude
	bounds.FilterDescendantsInstances={runtime,workspace.Terrain};bounds.RespectCanCollide=true
	local trainingStart=spawnCf*CFrame.new(0,3,-9)
	local frame=Fracture.frontWall(trainingStart,ground,function(cf,size)
		return #workspace:GetPartBoundsInBox(cf,size+Vector3.new(1,-.4,1),bounds)>0
	end)
	if frame then practice=collider(runtime,'RocketPracticeWall',Fracture.TestSize,frame,Color3.fromRGB(180,171,158),Enum.Material.Concrete,true) end
end
local rack=nil;local holder,launcher=nil,nil
local cooldown=-math.huge
local spot=spawnCf*CFrame.new(4,0,-4)
local height=ground(spot.Position,45) or (spawnCf.Y-.5)
local storageFrame=CFrame.new(spot.Position.X,height,spot.Position.Z)*spawnCf.Rotation
local function avatar(player)
	local char=player.Character
	local hum=char and char:FindFirstChildOfClass('Humanoid')
	local root=char and char:FindFirstChild('HumanoidRootPart')
	if hum and hum.Health>0 and root then return char,hum,root end
	return nil
end
local showRack
local function returnLauncher(player,tool)
	if holder~=player or launcher~=tool then return end
	holder,launcher=nil,nil
	if tool.Parent then tool:Destroy() end
	task.delay(1.5,showRack)
end
showRack=function()
	if holder or rack then return end
	local stand=folder(runtime,'LauncherPickup');rack=stand
	local base=collider(stand,'PickupRack',Vector3.new(2.45,.34,4.8),storageFrame*CFrame.new(0,.18,0),
		Color3.fromRGB(73,78,73),Enum.Material.Metal,false)
	collider(stand,'RackRest',Vector3.new(1.2,1.15,.58),storageFrame*CFrame.new(0,.74,.7),base.Color,Enum.Material.Metal,false)
	local mount=Model.model(stand,storageFrame*CFrame.new(0,1.40,.45),true)
	local prompt=Instance.new('ProximityPrompt');prompt.Name='PickupLauncher'
	prompt.KeyboardKeyCode,prompt.ActionText,prompt.ObjectText=Enum.KeyCode.G,'줍기','바주카포'
	prompt.MaxActivationDistance,prompt.MaxIndicatorDistance,prompt.RequiresLineOfSight=14,38,false
	prompt.ClickablePrompt=false;prompt.Parent=mount
	prompt.Triggered:Connect(function(player)
		if rack~=stand or holder then return end
		local char,hum,root=avatar(player)
		local bag=player:FindFirstChildOfClass('Backpack')
		if not char or not bag or (root.CFrame.Position-mount.CFrame.Position).Magnitude>15 or hum.SeatPart then return end
		local tool=Instance.new('Tool');tool.Name='바주카포';tool.ToolTip='좌클릭 발사 · 1.15초 재장전'
		tool.CanBeDropped=false;tool.RequiresHandle=true
		tool.Grip=CFrame.new(0,-.13,.10)
		Model.model(tool,CFrame.new(),false)
		script.RocketLauncherClient:Clone().Parent=tool
		holder,launcher,cooldown=player,tool,-math.huge
		rack=nil;stand:Destroy()
		hum.Died:Once(function() returnLauncher(player,tool) end)
		tool.Destroying:Once(function()
			if launcher==tool then holder,launcher=nil,nil;task.delay(1.5,showRack) end
		end)
		tool.Parent=bag;hum:EquipTool(tool)
	end)
end
showRack()
Players.PlayerRemoving:Connect(function(player) if holder==player and launcher then returnLauncher(player,launcher) end end)
local flights={}
local function muzzleFx(body)
	local a,b=Instance.new('Attachment'),Instance.new('Attachment')
	a.Position,b.Position=Vector3.new(0,.13,0),Vector3.new(0,-.13,0)
	a.Parent,b.Parent=body,body
	local trail=Instance.new('Trail');trail.Attachment0,trail.Attachment1=a,b
	trail.Color=ColorSequence.new(Color3.fromRGB(255,198,99),Color3.fromRGB(91,86,78))
	trail.Transparency=NumberSequence.new(.12,1);trail.Lifetime=.25;trail.FaceCamera=true;trail.LightEmission=.55;trail.Parent=body
end
remote.OnServerEvent:Connect(function(player,target)
	if player~=holder or not launcher or not player.Character or launcher.Parent~=player.Character then return end
	local char,hum,root=avatar(player)
	if not char or hum.SeatPart or #flights>=8 then return end
	local now=os.clock();if now-cooldown<Flight.Interval then return end
	local handle=launcher:FindFirstChild('Handle')
	local mouth=handle and handle:FindFirstChild('Muzzle')
	local head=char:FindFirstChild('Head')
	local eye=if head and head:IsA('BasePart') then head.CFrame.Position else root.CFrame.Position+Vector3.yAxis*.65
	local direction=Flight.aim(eye,target);if not direction then return end
	-- At close range the barrel can overlap the side of the shooter or a
	-- nearby wall. Advance from the sightline, and sweep that short span too.
	local mouthOffset=mouth and mouth.WorldPosition-eye or Vector3.zero
	local advance=math.clamp(mouthOffset:Dot(direction),0,math.min(4,(target-eye).Magnitude))
	local offset=direction*advance
	local origin=eye+offset
	cooldown=now
	local query=RaycastParams.new();query.FilterType=Enum.RaycastFilterType.Exclude
	query.FilterDescendantsInstances={char,rockets,rubble};query.RespectCanCollide=true
	local blocked=if offset.Magnitude>.01 then workspace:Raycast(eye,offset,query) else nil
	if blocked then detonate(blocked,eye);return end
	local body=Model.rocket(rockets,CFrame.lookAt(origin,origin+direction));muzzleFx(body)
	table.insert(flights,{Part=body,Position=origin,Direction=direction,Age=0,Query=query,From=eye})
end)
Run.Heartbeat:Connect(function(dt)
	for i=#flights,1,-1 do
		local item=flights[i]
		local hit,done=Flight.advance(item,dt,function(origin,segment) return workspace:Raycast(origin,segment,item.Query) end)
		if done then
			table.remove(flights,i);item.Part:Destroy()
			if hit then detonate(hit,item.From) end
		else item.Part.CFrame=CFrame.lookAt(item.Position,item.Position+item.Direction)*CFrame.Angles(0,math.pi*.5,0) end
	end
end)
