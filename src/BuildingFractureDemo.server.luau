-- [BoraBuildingFracture] A Studio Play-only, single-use wall spawned in front of the tester.
local Run=game:GetService('RunService')
if not Run:IsStudio() then return end
local Debris=game:GetService('Debris')
local Players=game:GetService('Players')
local Fracture=require(script.BuildingFracture)({Instance=Instance,Vector3=Vector3,CFrame=CFrame,Enum=Enum})
local effects={
	Expire=function(item,lifetime) Debris:AddItem(item,lifetime) end,
	Kick=function(part,direction,spin)
		if part:CanSetNetworkOwnership() then part:SetNetworkOwner(nil) end
		part:ApplyImpulse(direction*part.AssemblyMass)
		part:ApplyAngularImpulse(spin*part.AssemblyMass)
	end,
}
local function spawn(player,character,root)
	local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances={character};ray.RespectCanCollide=true
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Exclude
	-- Terrain occupies a large bounds box; its actual surface is sampled by the rays.
	overlap.FilterDescendantsInstances={character,workspace.Terrain};overlap.RespectCanCollide=true
	local cf=Fracture.frontWall(root.CFrame,function(point)
		local hit=workspace:Raycast(point+Vector3.yAxis*4,-Vector3.yAxis*22,ray)
		if hit and hit.Normal.Y>=.94 then return hit.Position.Y end
		return nil
	end,function(frame,size)
		return #workspace:GetPartBoundsInBox(frame*CFrame.new(0,.04,0),size+Vector3.new(2,-.4,2),overlap)>0
	end)
	if not cf then warn('[BoraBuildingFracture] 캐릭터 앞에 벽을 놓을 빈 지면이 없습니다.');return end
	local folder=Instance.new('Folder');folder.Name='BoraFracturePlayDemo'
	local wall=Instance.new('Part');wall.Name='TestWall'
	wall.Anchored,wall.Size,wall.CFrame=true,Fracture.TestSize,cf
	wall.Material,wall.Color=Enum.Material.Concrete,Color3.fromRGB(184,177,163)
	wall.TopSurface,wall.BottomSurface=Enum.SurfaceType.Smooth,Enum.SurfaceType.Smooth
	wall.Parent=folder
	local marker=Instance.new('Part');marker.Name='WallBreakPrompt'
	marker.Size,marker.Transparency,marker.Anchored=Vector3.new(.25,.25,.25),1,true
	marker.CanCollide,marker.CanTouch,marker.CanQuery=false,false,false
	marker.CFrame=cf*CFrame.new(wall.Size.X*.5+.3,-wall.Size.Y*.5+4.1,0)
	marker.Parent=folder
	local prompt=Instance.new('ProximityPrompt');prompt.Name='BreakWallTest'
	prompt.KeyboardKeyCode=Enum.KeyCode.E
	prompt.ActionText,prompt.ObjectText='벽 부수기','파손 테스트'
	prompt.MaxActivationDistance,prompt.HoldDuration,prompt.RequiresLineOfSight=14,.45,true
	prompt.Parent=marker
	folder.Parent=workspace
	local used=false
	prompt.Triggered:Connect(function(activator)
		if used or activator~=player or not wall:IsDescendantOf(folder) then return end
		local char=player.Character
		local h=char and char:FindFirstChildOfClass('Humanoid')
		local avatar=char and char:FindFirstChild('HumanoidRootPart')
		if not h or h.Health<=0 or not avatar or (avatar.CFrame.Position-marker.CFrame.Position).Magnitude>15 then return end
		used=true;prompt.Enabled=false
		local result,err=Fracture.breakWall(wall,avatar.CFrame.Position,folder,effects)
		if not result then warn('[BoraBuildingFracture] '..err) end
		marker:Destroy()
	end)
end
local started=false
local function ready(player)
	if started then return end
	local function characterAdded(character)
		local root=character:WaitForChild('HumanoidRootPart',10)
		if not root then return end
		task.wait(.3)
		if started or not root.Parent or player.Character~=character then return end
		started=true;spawn(player,character,root)
	end
	player.CharacterAdded:Connect(characterAdded)
	if player.Character then task.spawn(characterAdded,player.Character) end
end
Players.PlayerAdded:Connect(ready)
for _,player in Players:GetPlayers() do ready(player) end
