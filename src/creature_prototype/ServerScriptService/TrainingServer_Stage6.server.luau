local Players=game:GetService("Players")
local Growth=require(game.ReplicatedStorage:WaitForChild("TrainingRules_Stage6"))
local root=workspace:WaitForChild("CentralHub_Stage5"):WaitForChild("Stage6_Training")
local zones={{name="Speed",machine=root:WaitForChild("SpeedTreadmill")},{name="Strength",machine=root:WaitForChild("StrengthMachine")}}
for _,z in ipairs(zones) do z.surface=z.machine:WaitForChild("TrainingSurface") end
local sessions={}
local Economy=require(game.ServerScriptService:WaitForChild("PlayerEconomy_Stage11"))
local getter=Instance.new("BindableFunction"); getter.Name="GetTrainingStats"; getter.Parent=script
getter.OnInvoke=function(p) local s=sessions[p]; return {speed=s and s.speed or 0,strength=s and s.strength or 0,rebirths=s and s.rebirths or 0,highest=s and s.highest or 0,equipment=Economy.Snapshot(p)} end
local function publish(p,s)
 s.highest=math.max(s.highest or 0,s.speed)
 p:SetAttribute("HighestSpeedTraining",s.highest)
 p:SetAttribute("RebirthCount",s.rebirths)
 p:SetAttribute("TrainingMultiplier",Growth.Multiplier(s.rebirths))
 p:SetAttribute("TrainingGainPerSecond",Growth.Multiplier(s.rebirths)*Economy.Multiplier(p))
 p:SetAttribute("RebirthRequirement",Growth.Requirement(s.rebirths))
 p:SetAttribute("SpeedTraining",s.speed); p:SetAttribute("StrengthTraining",s.strength)
 p:SetAttribute("TrainingMode",s.mode or ""); p:SetAttribute("TrainingTickSerial",s.serial)
 local c=p.Character; local hum=c and c:FindFirstChildOfClass("Humanoid")
 if hum then hum.WalkSpeed=Growth.WalkSpeed(s.speed) end
 p:SetAttribute("TrainingWalkSpeed",Growth.WalkSpeed(s.speed))
 local folder=p:FindFirstChild("SeaCreatures_Stage3")
 if folder then for _,r in ipairs(folder:GetChildren()) do local size=r:GetAttribute("SizeScale"); if size then r:SetAttribute("CurrentBasePower",Growth.Power(size,s.strength,r:GetAttribute("SpeciesId"))) end end end
 local backpack=p:FindFirstChildOfClass("Backpack")
 for _,container in ipairs({c or false,backpack or false}) do
  if container then for _,tool in ipairs(container:GetChildren()) do if tool:IsA("Tool") and tool:GetAttribute("SeaCreature") then
   local size=tool:GetAttribute("SizeScale"); local original=tool:GetAttribute("OriginalBasePower") or tool:GetAttribute("BasePower")
   local power=Growth.Power(size,s.strength,tool:GetAttribute("SpeciesId"))
   tool:SetAttribute("CurrentBasePower",power)
   tool.ToolTip=string.format("%.2f배 · %s · 원래 %d / 현재 %d",size,tool:GetAttribute("Trait"),original,power)
  end end end
 end
end
local beginAction=Instance.new("BindableFunction"); beginAction.Name="BeginGrowthAction"; beginAction.Parent=script
local endAction=Instance.new("BindableFunction"); endAction.Name="EndGrowthAction"; endAction.Parent=script
beginAction.OnInvoke=function(p)
 local s=sessions[p]; if not s or s.rebirthing or s.action then return nil end
 s.token+=1; s.action=s.token; return s.action
end
endAction.OnInvoke=function(p,token) local s=sessions[p]; if s and s.action==token then s.action=nil end end
local remote=game.ReplicatedStorage:WaitForChild("Rebirth_Stage7")
local request=remote:WaitForChild("Request"); local response=remote:WaitForChild("Result")
local function respond(p,ok,text)
 p:SetAttribute("LastRebirthMessage",text)
 response:FireClient(p,{success=ok,text=text})
end
request.OnServerEvent:Connect(function(p)
 local s=sessions[p]; if not s then return end
 if os.clock()-s.lastRequest<.3 then return end
 s.lastRequest=os.clock()
 if s.rebirthing or s.action then respond(p,false,"다른 처리가 끝난 뒤 다시 시도하세요"); return end
 s.rebirthing=true
 local ok,err=xpcall(function()
  local arena=workspace.CentralHub_Stage5.Stage4_Exhibition
  if arena:GetAttribute("Busy") and arena:GetAttribute("ChallengerUserId")==p.UserId then respond(p,false,"전투가 끝난 뒤 환생할 수 있어요"); return end
  local c=p.Character; local hum=c and c:FindFirstChildOfClass("Humanoid"); local hrp=c and c:FindFirstChild("HumanoidRootPart")
  if not hum or hum.Health<=0 or not hrp then respond(p,false,"살아 있는 캐릭터로 다시 시도하세요"); return end
  local required=Growth.Requirement(s.rebirths)
  if s.speed<required or s.strength<required then
   respond(p,false,string.format("부족한 훈련치 · 속도 %.1f / 힘 %.1f",math.max(0,required-s.speed),math.max(0,required-s.strength))); return
  end
  -- No yielding operations from this condition check through state publication and relocation.
  s.rebirths+=1; s.speed=0; s.strength=0; s.mode=nil; s.elapsed=0
  s.blockedUntil=os.clock()+.5
  publish(p,s)
  hrp.AssemblyLinearVelocity=Vector3.zero; hrp.AssemblyAngularVelocity=Vector3.zero
  c:PivotTo(workspace.SpawnLocation.CFrame+Vector3.new(0,3.2,0))
  hum.WalkSpeed=16
  respond(p,true,string.format("환생 완료! 훈련 배율 %.1f배",Growth.Multiplier(s.rebirths)))
 end,debug.traceback)
 s.rebirthing=false
 if not ok then warn(err); respond(p,false,"환생 처리 중 오류가 발생했습니다") end
end)
local function init(p)
 if sessions[p] then return end
 local s={speed=0,strength=0,highest=0,rebirths=0,mode=nil,elapsed=0,serial=0,token=0,lastRequest=-math.huge}; sessions[p]=s; publish(p,s)
 p.CharacterRemoving:Connect(function() s.mode=nil; s.elapsed=0; p:SetAttribute("TrainingMode","") end)
 p.CharacterAdded:Connect(function(c)
  s.mode=nil; s.elapsed=0; p:SetAttribute("TrainingMode","")
  task.spawn(function() local h=c:WaitForChild("Humanoid",10); if h and p.Character==c then h.WalkSpeed=Growth.WalkSpeed(s.speed); publish(p,s) end end)
 end)
end
Players.PlayerAdded:Connect(init); Players.PlayerRemoving:Connect(function(p) sessions[p]=nil end)
for _,p in ipairs(Players:GetPlayers()) do init(p) end
local function modeFor(p)
 local c=p.Character; local hum=c and c:FindFirstChildOfClass("Humanoid"); local hrp=c and c:FindFirstChild("HumanoidRootPart")
 if not hum or hum.Health<=0 or not hrp or hum.FloorMaterial==Enum.Material.Air then return nil end
 local expected=hrp.Size.Y/2+hum.HipHeight
 if hum.RigType==Enum.HumanoidRigType.R6 then expected=hrp.Size.Y/2+2 end
 local params=RaycastParams.new(); params.FilterType=Enum.RaycastFilterType.Exclude; params.FilterDescendantsInstances={c}; params.RespectCanCollide=true
 for _,z in ipairs(zones) do
  local pos=z.surface.CFrame:PointToObjectSpace(hrp.Position)
  if math.abs(pos.X)<=3 and math.abs(pos.Z)<=3.3 then
   local hit=workspace:Raycast(hrp.Position,Vector3.new(0,-8,0),params)
   if hit and hit.Instance==z.surface and math.abs((hrp.Position.Y-hit.Position.Y)-expected)<=.6 then return z.name end
  end
 end
 return nil
end
local elapsed=0
game:GetService("RunService").Heartbeat:Connect(function(dt)
 elapsed+=dt; if elapsed<.1 then return end; local step=elapsed; elapsed=0
 local active={Speed=0,Strength=0}
 for p,s in pairs(sessions) do
  if not s.action and not s.rebirthing then
  local mode=os.clock()>=(s.blockedUntil or 0) and modeFor(p) or nil
  if mode~=s.mode then s.mode=mode; s.elapsed=0; p:SetAttribute("TrainingMode",mode or "")
  elseif mode then
   s.elapsed+=step
   if s.elapsed>=1 then s.elapsed-=1; local gain=Growth.Multiplier(s.rebirths)*Economy.Multiplier(p); if mode=="Speed" then s.speed+=gain else s.strength+=gain end; s.serial+=1; publish(p,s) end
  end
  if mode then active[mode]+=1 end
  end
 end
 for _,z in ipairs(zones) do z.machine:SetAttribute("ActiveUsers",active[z.name]) end
end)

-- Equipment requests share the capture/equip/rebirth action lock.
local upgrades=game.ReplicatedStorage:WaitForChild("TrainingUpgrade_Stage11")
upgrades.Request.OnServerEvent:Connect(function(p,expectedVersion,...)
 local s=sessions[p]; if not s then return end
 local function reply(ok,text)
  upgrades.Result:FireClient(p,{success=ok,text=text,state=Economy.Snapshot(p)})
 end
 if select("#",...)~=0 then reply(false,"잘못된 구매 요청이에요"); return end
 if os.clock()-(s.lastUpgrade or -math.huge)<.25 then reply(false,"잠시 뒤 다시 눌러주세요"); return end
 s.lastUpgrade=os.clock()
 if s.rebirthing or s.action then reply(false,"다른 처리가 끝난 뒤 다시 시도하세요"); return end
 s.token+=1; local token=s.token; s.action=token
 local ok,err=xpcall(function()
  local c=p.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
  if not h or h.Health<=0 or not r then reply(false,"살아 있는 캐릭터로 다시 시도하세요"); return end
  local near=false
  for _,z in ipairs(zones) do if (r.Position-z.surface.Position).Magnitude<=18 then near=true end end
  if not near then reply(false,"중앙 훈련 기구 근처에서 강화하세요"); return end
  local arena=workspace.CentralHub_Stage5.Stage4_Exhibition
  if arena:GetAttribute("Busy") and arena:GetAttribute("ChallengerUserId")==p.UserId then reply(false,"전투가 끝난 뒤 강화할 수 있어요"); return end
  local purchased,text=Economy.Purchase(p,expectedVersion)
  if purchased then publish(p,s) end
  reply(purchased,text)
 end,debug.traceback)
 if s.action==token then s.action=nil end
 if not ok then warn(err); reply(false,"강화 정보를 다시 확인하세요") end
end)
