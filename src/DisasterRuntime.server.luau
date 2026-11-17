-- [BoraDisaster] Server-owned meteor survival in the existing neighborhood.
local Players=game:GetService('Players')
local Replicated=game:GetService('ReplicatedStorage')
local TweenService=game:GetService('TweenService')
local Debris=game:GetService('Debris')
local World=workspace
local Round=require(script.DisasterRound)
local destruction=script.Parent:WaitForChild('BoraRocketRuntime'):WaitForChild('BuildingDestruction')
local radius,strikeRadius=133,17
local lead,fall,pause=1.30,.55,.35
local config={Intermission=12,Warning=6,Active=44,Results=7,StrikeTime=lead+fall+pause}
local rng=Random.new()

local function folder(parent,name)
	local object=Instance.new('Folder')
	object.Name,object.Parent=name,parent
	return object
end

local buildings=World:WaitForChild('BoraNeighborhood_01'):WaitForChild('Buildings')
local lobby=World:WaitForChild('CenterSpawn')
local originals={}
local center=Vector3.zero
local anchorCount=0
for _,building in buildings:GetChildren() do
	local origin=building:FindFirstChild('BuildingOrigin')
	if building:IsA('Model') and building:GetAttribute('AssetKind')=='BoraBuilding' and origin and origin:IsA('BasePart') then
		originals[building.Name]=assert(building:Clone())
		center+=origin.Position
		anchorCount+=1
	end
end
assert(anchorCount>0 and lobby:IsA('BasePart'),'Bora disaster arena is missing its buildings or lobby spawn')
center/=anchorCount

local arena=folder(World,'BoraDisasterPlay')
local rubble=folder(arena,'Rubble')
local effects=folder(arena,'Effects')
local state=folder(Replicated,'BoraDisasterState')
local terrainCast=RaycastParams.new()
terrainCast.FilterType=Enum.RaycastFilterType.Exclude
terrainCast.RespectCanCollide=true
local function castParams()
	local ignore={arena}
	for _,player in Players:GetPlayers() do
		if player.Character then table.insert(ignore,player.Character) end
	end
	terrainCast.FilterDescendantsInstances=ignore
	return terrainCast
end

local function groundAt(position,params)
	local sky=Vector3.new(position.X,center.Y+100,position.Z)
	return World:Raycast(sky,-Vector3.yAxis*185,params)
end

local function part(name,size,frame,color,transparency,shape)
	local p=Instance.new('Part')
	p.Name,p.Shape,p.Size,p.CFrame=name,shape or Enum.PartType.Block,size,frame
	p.Anchored,p.CanCollide,p.CanTouch,p.CanQuery=true,false,false,false
	p.Material,p.Color,p.Transparency=Enum.Material.Neon,color,transparency
	p.Parent=effects
	return p
end

local function buildBoundary()
	local yellow=Color3.fromRGB(255,194,85)
	local params=castParams()
	for i=0,47 do
		local angle=i*math.pi/24
		local outward=Vector3.new(math.cos(angle),0,math.sin(angle))
		local hit=groundAt(center+outward*radius,params)
		if hit then
			local pos=hit.Position+Vector3.yAxis*.16
			local segment=part('ArenaBoundary',Vector3.new(.26,.18,14),CFrame.lookAt(pos,pos+outward:Cross(Vector3.yAxis)),yellow,.29)
			segment.Parent=arena
		end
	end
end
buildBoundary()

local function health(player,character)
	if player.Parent~=Players or not character or player.Character~=character or not character.Parent then return nil end
	local humanoid=character:FindFirstChildOfClass('Humanoid')
	local root=character:FindFirstChild('HumanoidRootPart')
	if not humanoid or humanoid.Health<=0 or not root or not root:IsA('BasePart') then return nil end
	return humanoid,root
end

local function horizontal(v) return Vector3.new(v.X,0,v.Z) end
local function inArena(position)
	return horizontal(position-center).Magnitude<=radius+2
end

local function characterTo(humanoid,root,character,frame)
	humanoid.Sit=false
	character:PivotTo(frame)
	root.AssemblyLinearVelocity=Vector3.zero
	root.AssemblyAngularVelocity=Vector3.zero
end

local function spawnPoints()
	local out={}
	local params=castParams()
	for i=0,23 do
		local angle=i*math.pi/12
		local hit=groundAt(center+Vector3.new(math.cos(angle),0,math.sin(angle))*47,params)
		if hit and hit.Position.Y-center.Y<3.5 and hit.Normal.Y>.83 then table.insert(out,hit.Position) end
	end
	assert(#out>0,'No safe arena entry points')
	return out
end
local entries=spawnPoints()

local function phase(name,duration,entrants,alive)
	state:SetAttribute('Entrants',entrants or 0)
	state:SetAttribute('Alive',alive or 0)
	state:SetAttribute('EndsAt',if duration>0 then World:GetServerTimeNow()+duration else 0)
	state:SetAttribute('Phase',name)
end

local activity,damage
local function enroll()
	local roster={}
	local count=0
	activity={}
	local round=activity
	damage=require(destruction)({Instance=Instance,Vector3=Vector3,CFrame=CFrame,Enum=Enum},{
		HasRoom=function() return #rubble:GetChildren()<100 end,
		Release=function(piece,velocity,spin)
			piece.CanTouch=false
			piece.Parent=rubble
			piece.Anchored=false
			if piece:CanSetNetworkOwnership() then piece:SetNetworkOwner(nil) end
			piece:ApplyImpulse(velocity*piece.AssemblyMass)
			piece:ApplyAngularImpulse(spin*piece.AssemblyMass)
			Debris:AddItem(piece,9)
		end,
		Schedule=function(delay,callback)
			task.delay(delay,function() if activity==round then callback() end end)
		end,
		Collapse=function() end,
	})
	for _,player in Players:GetPlayers() do
		local character=player.Character
		local humanoid,root=health(player,character)
		if humanoid then
			local point=entries[count%#entries+1]+Vector3.yAxis*4
			characterTo(humanoid,root,character,CFrame.lookAt(point,Vector3.new(center.X,point.Y,center.Z)))
			humanoid.Health=humanoid.MaxHealth
			player:SetAttribute('BoraInRound',true)
			roster[player]=character
			count+=1
		end
	end
	round.roster=roster
	return roster
end

local function isAlive(player,character)
	local humanoid,root=health(player,character)
	if humanoid and inArena(root.Position) then return true end
	if humanoid then humanoid.Health=0 end
	if player.Parent==Players and player:GetAttribute('BoraInRound') then player:SetAttribute('BoraInRound',false) end
	return false
end

local function nextTarget(alive,params)
	activity.strikes=(activity.strikes or 0)+1
	-- Space out structural hits so the street stays navigable early in the round.
	if activity.strikes%3==1 then
		local targets={}
		for _,building in buildings:GetChildren() do
			if originals[building.Name] and building:FindFirstChild('BuildingOrigin') then table.insert(targets,building) end
		end
		if #targets>0 then
			local pivot=targets[rng:NextInteger(1,#targets)].BuildingOrigin.Position
			local hit=groundAt(pivot+Vector3.new(rng:NextNumber(-8,8),0,rng:NextNumber(-8,8)),params)
			if hit then return hit end
		end
	end
	local player=alive[rng:NextInteger(1,#alive)]
	local _,root=health(player,activity.roster[player])
	local spot=root and root.Position or center
	local angle=rng:NextNumber(0,2*math.pi)
	local offset=horizontal(spot-center)+Vector3.new(math.cos(angle),0,math.sin(angle))*rng:NextNumber(8,21)
	if offset.Magnitude>radius-7 then offset=offset.Unit*(radius-7) end
	return groundAt(center+offset,params)
end

local function strike(alive)
	local params=castParams()
	local target=nextTarget(alive,params)
	if not target then task.wait(config.StrikeTime);return end
	local position=target.Position
	local red=Color3.fromRGB(255,95,58)
	local marker=part('ImpactWarning',Vector3.new(.11,strikeRadius*2,strikeRadius*2),
		CFrame.new(position+Vector3.yAxis*.14)*CFrame.Angles(0,0,math.pi/2),red,.66,Enum.PartType.Cylinder)
	local sky=position+Vector3.yAxis*77
	task.wait(lead)
	local meteor=part('FallingMeteor',Vector3.one*4.8,CFrame.new(sky),red,0,Enum.PartType.Ball)
	local light=Instance.new('PointLight')
	light.Color,light.Brightness,light.Range=red,3,25
	light.Parent=meteor
	TweenService:Create(meteor,TweenInfo.new(fall,Enum.EasingStyle.Linear),{Position=position}):Play()
	task.wait(fall)
	meteor:Destroy()
	marker:Destroy()

	params=castParams()
	local impact=World:Raycast(sky,position-sky-Vector3.yAxis*50,params)
	if impact then
		position=impact.Position
		for player,character in activity.roster do
			local humanoid,root=health(player,character)
			if humanoid and inArena(root.Position) then
				local distance=(root.Position-position).Magnitude
				if distance<strikeRadius then
					local origin=position+Vector3.yAxis*1.7
					local cover=World:Raycast(origin,root.Position-origin,params)
					local amount=115*(1-distance/strikeRadius)*(if cover then .18 else 1)
					humanoid:TakeDamage(amount)
				end
			end
		end
		local flash=part('ImpactFlash',Vector3.one*5,CFrame.new(position),red,.18,Enum.PartType.Ball)
		TweenService:Create(flash,TweenInfo.new(.38),{Size=Vector3.one*strikeRadius,Transparency=1}):Play()
		Debris:AddItem(flash,.45)
		local hitBuilding=impact.Instance
		while hitBuilding and hitBuilding.Parent~=buildings do hitBuilding=hitBuilding.Parent end
		for _,building in buildings:GetChildren() do
			if originals[building.Name] then
				local cf,size=building:GetBoundingBox()
				if damage.distance(cf,size,position)<=damage.BlastRadius then
					local direct=if building==hitBuilding then impact.Instance else nil
					damage.blast(building,position,direct,sky)
				end
			end
		end
	end
	task.wait(pause)
end

local function finish(roster,winners)
	activity=nil
	for _,player in winners do
		player:SetAttribute('BoraSurvivals',(player:GetAttribute('BoraSurvivals') or 0)+1)
	end
	rubble:ClearAllChildren()
	effects:ClearAllChildren()
	for _,building in buildings:GetChildren() do
		local original=originals[building.Name]
		if original then
			local restored=original:Clone()
			building:Destroy()
			restored.Parent=buildings
		end
	end
	-- Let the building runtime release any elevator riders before teleporting them.
	task.wait()
	local i=0
	for player,character in roster do
		if player.Parent==Players then player:SetAttribute('BoraInRound',false) end
		local humanoid,root=health(player,character)
		if humanoid then
			characterTo(humanoid,root,character,lobby.CFrame*CFrame.new(i%5*4-8,5,math.floor(i/5)*4))
			i+=1
		end
	end
	damage=nil
end

local function clock() return World:GetServerTimeNow() end
local roundWorld={
	now=clock,wait=task.wait,phase=phase,enroll=enroll,isAlive=isAlive,strike=strike,finish=finish,
	update=function(alive) state:SetAttribute('Alive',alive) end,
}
while true do
	phase('Waiting',0)
	while #Players:GetPlayers()==0 do Players.PlayerAdded:Wait() end
	Round.run(config,roundWorld)
end
