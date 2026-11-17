-- [BoraBuilding] elevator runtime. Geometry is authored in Studio; Play animates it.
local Players=game:GetService('Players');local Run=game:GetService('RunService')
local Replicated=game:GetService('ReplicatedStorage')
local Motion=require(script.BuildingElevatorMotion)
local Actor=require(script.BuildingElevatorActor)({CFrame=CFrame,Vector3=Vector3},Motion)
local remote=Replicated:FindFirstChild('BoraBuildingElevator')
if remote then assert(remote:IsA('RemoteEvent') and remote:GetAttribute('BoraOwned'),'Elevator remote name collision')
else remote=Instance.new('RemoteEvent');remote.Name='BoraBuildingElevator';remote:SetAttribute('BoraOwned',true);remote.Parent=Replicated end
local actors={};local requests={}
local function characters() local out={};for _,p in Players:GetPlayers() do if p.Character then table.insert(out,p.Character) end end;return out end
local function near(player,part)
	local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
	local h=player.Character and player.Character:FindFirstChildOfClass('Humanoid')
	return root and h and h.Health>0 and (root.CFrame.Position-part.CFrame.Position).Magnitude<=10
end
local function register(model)
	if not model:IsA('Model') or model:GetAttribute('BoraElevator')~=true or actors[model] then return end
	if not model:FindFirstChild('ShaftOrigin') or not model:FindFirstChild('Cab') or not model:FindFirstChild('Stops') or not model:FindFirstChild('Landings') then return end
	local ok,actor=pcall(Actor.new,model,characters);if not ok then warn('[BoraBuilding] elevator: '..tostring(actor));return end
	actors[model]=actor
	for floor=1,#actor.State.Stops do
		local button=model.Landings['Floor_'..floor].CallButton
		table.insert(actor.Connections,button.Call.Triggered:Connect(function(player) if near(player,button) then Motion.request(actor.State,floor) end end))
	end
	table.insert(actor.Connections,model.Cab.ControlPanel.SelectFloor.Triggered:Connect(function(player)
		if actor:inside(player.Character) then remote:FireClient(player,'Open',model,#actor.State.Stops,actor.State.Floor) end
	end))
end
for _,model in workspace:GetDescendants() do register(model) end
workspace.DescendantAdded:Connect(function(item)
	if item:IsA('Model') then task.defer(function() if item:IsDescendantOf(workspace) then register(item) end end) end
end)
workspace.DescendantRemoving:Connect(function(item) local actor=actors[item];if actor then actor:destroy();actors[item]=nil end end)
remote.OnServerEvent:Connect(function(player,model,floor)
	local actor=actors[model];if not actor or not actor:inside(player.Character) then return end
	local now=os.clock();if now-(requests[player] or -math.huge)<.2 then return end;requests[player]=now
	Motion.request(actor.State,floor)
end)
Players.PlayerRemoving:Connect(function(player) requests[player]=nil end)
Run.Heartbeat:Connect(function(dt)
	for model,actor in actors do
		local ok,err=pcall(actor.step,actor,dt)
		if not ok then actor:destroy();actors[model]=nil;warn('[BoraBuilding] stopped elevator: '..tostring(err)) end
	end
end)
game:BindToClose(function() for _,actor in actors do actor:destroy() end end)
