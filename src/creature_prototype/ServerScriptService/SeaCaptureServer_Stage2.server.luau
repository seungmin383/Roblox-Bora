-- Stage 2: session-only capture; all rewards and validation live on the server.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local region = workspace:WaitForChild("SeaRegion_Stage1")
local exploration=region:WaitForChild("Stage8_Exploration")
local legendRoot=region:WaitForChild("Stage9_Legend")
local activeRitual=nil
local sites={
 {model=region:WaitForChild("Stage2_Collection"):WaitForChild("ActiveBeachSite"),zone="beach"},
 {model=exploration:WaitForChild("Active_coral"),zone="coral"},
 {model=exploration:WaitForChild("Active_far"),zone="far"},
 {model=legendRoot:WaitForChild("SeaDragonSite"),zone="far",legend=true},
}
for _,site in ipairs(sites) do site.anchor=site.model:WaitForChild("PromptAnchor"); site.prompt=site.anchor:WaitForChild(site.legend and "AwakenSeaDragon" or "FindCreature") end
local Catalog=require(ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local access=game.ServerScriptService:WaitForChild("SeaExplorationServer_Stage8"):WaitForChild("CheckAccess")
local resultEvent = ReplicatedStorage:WaitForChild("SeaCapture_Stage2"):WaitForChild("CaptureResult")
local templates = ServerStorage:WaitForChild("SeaCapture_Stage2"):WaitForChild("SpeciesTools_Stage8")
local HOLD_SECONDS = 0.95
local COOLDOWN = 3
local MAX_DISTANCE = 10
local sessions = {}
local Economy=require(game.ServerScriptService:WaitForChild("PlayerEconomy_Stage11"))
local Http=game:GetService("HttpService")
local rng=Random.new()
local equipEvent=ReplicatedStorage.SeaCapture_Stage2:WaitForChild("EquipIndividual")
local traits={"돌파","수호","기습"}
local Growth=require(ReplicatedStorage:WaitForChild("TrainingRules_Stage6"))
local getTraining=game.ServerScriptService:WaitForChild("TrainingServer_Stage6"):WaitForChild("GetTrainingStats")
local beginGrowth=game.ServerScriptService.TrainingServer_Stage6:WaitForChild("BeginGrowthAction")
local endGrowth=game.ServerScriptService.TrainingServer_Stage6:WaitForChild("EndGrowthAction")
local function strength(player) local stats=getTraining:Invoke(player); return stats and stats.strength or 0 end
for _, name in ipairs({"FirstCaptures","DuplicateCaptures","CanceledHolds","DistanceCancels","CooldownRejections","TimingRejections","AccessRejections","SeaDragonStarts","SeaDragonCancels","SeaDragonAwards"}) do script:SetAttribute(name,0) end
local function count(name) script:SetAttribute(name,(script:GetAttribute(name) or 0)+1) end
local function publish(player,s)
 player:SetAttribute("SeaDragonTraces",s.traces)
 Economy.Publish(player)
 player:SetAttribute("SeaSpeciesCount",s.speciesCount)
 player:SetAttribute("SeaHasCoralCrab",s.discovered.coral_crab==true)
 player:SetAttribute("SeaCooldownUntil",s.nextAt)
 player:SetAttribute("SeaCaptureCount",s.captures)
 player:SetAttribute("SeaIndividualCount",#s.order)
 player:SetAttribute("SeaEquippedId",s.equipped or "")
end
local lookup=Instance.new("BindableFunction"); lookup.Name="GetOwnedIndividual_Stage4"; lookup.Parent=script
lookup.OnInvoke=function(player,id)
 local s=sessions[player]; if not s then return nil end
 local record=s.records[id or s.equipped]; if not record then return nil end
 local trained=strength(player)
 if sessions[player]~=s or s.records[record.id]~=record then return nil end
 local copy=table.clone(record); copy.originalPower=record.power; copy.strengthAtSnapshot=trained; copy.power=Growth.Power(record.scale,trained,record.speciesId)
 return copy
end
local activity=Instance.new("BindableFunction"); activity.Name="GetActivity_Stage10"; activity.Parent=script
activity.OnInvoke=function(p) local s=sessions[p]; return {holding=s~=nil and s.hold~=nil} end
local function validCharacter(player,character,site)
 if player.Character ~= character then return false end
 local hum=character and character:FindFirstChildOfClass("Humanoid")
 local hrp=character and character:FindFirstChild("HumanoidRootPart")
 return hum and hum.Health>0 and hrp and (hrp.Position-site.anchor.Position).Magnitude<=MAX_DISTANCE
end
local function grantTool(player)
 local s=sessions[player]; local record=s and s.records[s.equipped]
 if not record then return end
 local backpack=player:FindFirstChildOfClass("Backpack")
 local character=player.Character
 local hum=character and character:FindFirstChildOfClass("Humanoid")
 if not backpack or not hum or hum.Health<=0 then return end
 local currentPower=Growth.Power(record.scale,strength(player),record.speciesId)
 local visualScale=record.scale*Catalog.VisualScale(record.speciesId,"ToolScale")
 if sessions[player]~=s or s.equipped~=record.id or player.Character~=character then return end
 for _,container in ipairs({backpack,character}) do
  for _,obj in ipairs(container:GetChildren()) do
   if obj:IsA("Tool") and (obj:GetAttribute("SeaCreature") or obj.Name=="산호게") then obj:Destroy() end
  end
 end
 local tool=templates[record.speciesId]:Clone(); tool.Name=Catalog.Get(record.speciesId).Name; tool:SetAttribute("SpeciesId",record.speciesId); tool.CanBeDropped=false
 tool:SetAttribute("VisualScale",visualScale); tool:SetAttribute("SeaCreature",true); tool:SetAttribute("IndividualId",record.id)
 tool:SetAttribute("SizeScale",record.scale); tool:SetAttribute("Trait",record.trait); tool:SetAttribute("BasePower",record.power); tool:SetAttribute("OriginalBasePower",record.power); tool:SetAttribute("CurrentBasePower",currentPower)
 for _,p in ipairs(tool:GetDescendants()) do
  if p:IsA("BasePart") then
   p.Size=p.Size*visualScale
   p.CFrame=CFrame.new(p.Position*visualScale)*p.CFrame.Rotation
   p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.Massless=true; p.Anchored=false
  end
 end
 tool.ToolTip=string.format("%.2f배 · %s · 원래 %d / 현재 %d",record.scale,record.trait,record.power,currentPower)
 tool.Parent=backpack; hum:EquipTool(tool)
end
local function equipIndividual(player,id)
 local s=sessions[player]
 if not s or type(id)~="string" or not s.records[id] then return end
 local now=os.clock()
 if now<(s.lastEquip or 0)+.15 then return end
 s.lastEquip=now
 if s.equipped==id then return end
 s.equipped=id; publish(player,s); grantTool(player)
end
equipEvent.OnServerEvent:Connect(function(player,id)
 local token=beginGrowth:Invoke(player); if not token then return end
 local ok,err=xpcall(function() equipIndividual(player,id) end,debug.traceback)
 endGrowth:Invoke(player,token); if not ok then warn(err) end
end)
local function init(player)
 if sessions[player] then return end
 local folder=Instance.new("Folder"); folder.Name="SeaCreatures_Stage3"; folder.Parent=player
 local s={traces=0,owned=false,discovered={},speciesCount=0,nextAt=0,captures=0,hold=nil,records={},order={},folder=folder}
 sessions[player]=s
 publish(player,s)
 player.CharacterRemoving:Connect(function() s.hold=nil; if activeRitual and activeRitual.player==player then activeRitual.canceled=true end end)
 player.CharacterAdded:Connect(function(character)
  task.spawn(function()
   player:WaitForChild("Backpack",10)
   if player.Character==character then grantTool(player) end
  end)
 end)
end
Players.PlayerAdded:Connect(init)
Players.PlayerRemoving:Connect(function(player) sessions[player]=nil end)
for _, player in ipairs(Players:GetPlayers()) do init(player) end

-- Stage 9: one non-yielding commit path for ordinary and legendary captures.
local function award(player,s,speciesId,trained,isLegend,zone)
 assert(sessions[player]==s and templates:FindFirstChild(speciesId),"Invalid award context")
 local scale=math.round(rng:NextNumber(.75,1.5)*100)/100
 local record={id=Http:GenerateGUID(false),speciesId=speciesId,scale=scale,trait=traits[rng:NextInteger(1,3)],power=Growth.Power(scale,0,speciesId)}
 local currentPower=Growth.Power(scale,trained,speciesId)
 local entry=Instance.new("Folder"); entry.Name=record.id
 for k,v in pairs({IndividualId=record.id,SpeciesId=speciesId,DisplayName=Catalog.Get(speciesId).Name,SizeScale=scale,Trait=record.trait,BasePower=record.power,OriginalBasePower=record.power,CurrentBasePower=currentPower,CaptureIndex=#s.order+1}) do entry:SetAttribute(k,v) end
 local first=not s.discovered[speciesId]; local autoEquip=not s.equipped
 -- No yielding from here until publication: record, coin, discovery and traces commit together.
 s.records[record.id]=record; table.insert(s.order,record.id); s.captures+=1; Economy.AwardCapture(player); s.owned=true
 if first then s.discovered[speciesId]=true; s.speciesCount+=1 end
 if isLegend then s.traces=0 elseif zone=="far" then s.traces=math.min(20,s.traces+1) end
 if autoEquip then s.equipped=record.id end
 entry.Parent=s.folder; publish(player,s)
 count(first and "FirstCaptures" or "DuplicateCaptures")
 if isLegend then count("SeaDragonAwards") end
 return record,first,autoEquip,currentPower
end
local function feedback(player,s,record,first,autoEquip,currentPower,isLegend)
 if autoEquip then grantTool(player) end
 resultEvent:FireClient(player,{kind=first and "New" or "Individual",legend=isLegend or false,traces=s.traces,species=Catalog.Get(record.speciesId).Name,speciesId=record.speciesId,id=record.id,scale=record.scale,trait=record.trait,power=currentPower,coins=Economy.Snapshot(player).coins,speciesCount=s.speciesCount,untilTime=s.nextAt})
end
local function notice(player,text)
 if player.Parent then player:SetAttribute("SeaAccessNotice",text); player:SetAttribute("SeaAccessNoticeUntil",workspace:GetServerTimeNow()+2.5) end
end
local function ritualValid(r)
 local p=r.player; local c=p.Character; local hum=c and c:FindFirstChildOfClass("Humanoid"); local hrp=c and c:FindFirstChild("HumanoidRootPart")
 return legendRoot.Parent==region and (not r.model or r.model.Parent==legendRoot) and activeRitual==r and not r.canceled and sessions[p]==r.state and r.state.legendAttempt==r and p.Parent and c==r.character and hum and hum.Health>0 and hrp and (hrp.Position-r.site.anchor.Position).Magnitude<=12
end
local function startRitual(player,s,site)
 if s.traces<20 then notice(player,string.format("해신룡 흔적 %d/20 · 먼바다 포획으로 모으세요",s.traces)); return end
 if activeRitual then notice(player,"다른 탐험가의 해신룡이 등장 중이에요. 잠시 기다려 주세요"); return end
 local arena=workspace.CentralHub_Stage5.Stage4_Exhibition
 if arena:GetAttribute("Busy") and arena:GetAttribute("ChallengerUserId")==player.UserId then notice(player,"전투가 끝난 뒤 깨울 수 있어요"); return end
 local r={player=player,state=s,site=site,character=player.Character,committed=false}
 activeRitual=r; s.legendAttempt=r
 s.nextAt=workspace:GetServerTimeNow()+5.5; publish(player,s)
 player:SetAttribute("SeaDragonRitual",true)
 legendRoot:SetAttribute("RitualBusy",true); legendRoot:SetAttribute("RitualOwnerId",player.UserId); legendRoot:SetAttribute("RitualOwnerName",player.DisplayName)
 count("SeaDragonStarts")
 local ok,err=xpcall(function()
  assert(ritualValid(r),"RITUAL_CANCELED")
  local model=ReplicatedStorage.CreaturePreviews_Stage8.sea_dragon:Clone(); model.Name="AwakeningSeaDragon"; r.model=model
  model:SetAttribute("OwnerUserId",player.UserId); model:SetAttribute("OwnerName",player.DisplayName)
  model:ScaleTo(Catalog.VisualScale("sea_dragon","RevealScale")); model:PivotTo(CFrame.new(320,4,0))
  local colors={}
  for _,p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; colors[p]=p.Color; p.Color=Color3.fromRGB(9,37,58); p.Transparency=.8 end end
  local label=region["04_CollectionMarkers"].Collect_01_Beach.MarkerTop.PointLabel:Clone()
  label.Name="RequesterLabel"; label.AlwaysOnTop=false; label.MaxDistance=100; label.Size=UDim2.fromOffset(240,52); label.StudsOffset=Vector3.new(0,7,0); label.Label.Text=player.DisplayName.."의 해신룡"; label.Parent=model.Head
  model.Parent=legendRoot
  for i=1,48 do
   assert(ritualValid(r),"RITUAL_CANCELED")
   local t=i*.1; local rise=math.clamp((t-.6)/2,0,1); local reveal=math.clamp((t-2)/1.4,0,1)
   model:PivotTo(CFrame.new(320,4+14*rise+math.sin(t*2)*.2,0)*CFrame.Angles(0,math.pi,0))
   for p,color in pairs(colors) do p.Color=Color3.fromRGB(9,37,58):Lerp(color,reveal); p.Transparency=.8*(1-rise) end
   legendRoot.TraceHalo.Transparency=.9-.45*rise
   player:SetAttribute("SeaDragonRitualPhase",t<.7 and "바다가 잠잠해집니다…" or t<2.6 and "큰 실루엣이 올라옵니다…" or "해신룡이 모습을 드러냅니다!")
   task.wait(.1)
  end
  local trained=strength(player)
  assert(ritualValid(r) and s.traces>=20 and not r.committed,"RITUAL_CANCELED")
  local record,first,autoEquip,currentPower=award(player,s,"sea_dragon",trained,true,"far")
  r.committed=true
  feedback(player,s,record,first,autoEquip,currentPower,true)
 end,debug.traceback)
 -- Every exit releases the one shared scene lock; a committed reward is never rolled back or repeated.
 if r.model then r.model:Destroy() end
 if s.legendAttempt==r then s.legendAttempt=nil end
 if activeRitual==r then activeRitual=nil; legendRoot:SetAttribute("RitualBusy",false); legendRoot:SetAttribute("RitualOwnerId",0); legendRoot:SetAttribute("RitualOwnerName",""); legendRoot.TraceHalo.Transparency=.92 end
 if player.Parent then
  player:SetAttribute("SeaDragonRitual",false); player:SetAttribute("SeaDragonRitualPhase","")
  if not r.committed and sessions[player]==s then s.nextAt=workspace:GetServerTimeNow()+.8; publish(player,s); notice(player,"깨우기 취소 · 흔적은 그대로 보관됩니다"); count("SeaDragonCancels") end
 end
 if not ok and not string.find(tostring(err),"RITUAL_CANCELED",1,true) then warn(err) end
end

for _,site in ipairs(sites) do
local prompt=site.prompt
prompt.PromptButtonHoldBegan:Connect(function(player)
 local s=sessions[player]
 if not s then return end
 if site.legend and (s.traces<20 or activeRitual) then notice(player,activeRitual and "다른 탐험가의 출현 중이에요. 잠시 기다려 주세요" or string.format("해신룡 흔적 %d/20 · 먼바다 포획으로 모으세요",s.traces)); return end
 if workspace:GetServerTimeNow()<s.nextAt then
  count("CooldownRejections")
  resultEvent:FireClient(player,{kind="Cooldown",untilTime=s.nextAt})
  return
 end
 local started=os.clock(); local character=player.Character
 if not access:Invoke(player,site.zone) then count("AccessRejections"); return end
 if not validCharacter(player,character,site) then return end
 if not s.hold then s.hold={started=started,character=character,site=site} end
end)
prompt.PromptButtonHoldEnded:Connect(function(player)
 local s=sessions[player]
 local h=s and s.hold
 if not h or h.site~=site then return end
 local now=os.clock()
 if now-h.started<HOLD_SECONDS then
  s.hold=nil
  count("CanceledHolds")
 else
  -- Engine completion and hold-ended can arrive in either order.
  -- Only an already-completed hold gets this tiny ordering grace window.
  h.endedAt=now
  task.delay(0.12,function()
   if sessions[player]==s and s.hold==h then s.hold=nil; count("CanceledHolds") end
  end)
 end
end)
local function captureTriggered(player)
 local s=sessions[player]
 if not s then return end
 local now=os.clock()
 local serverNow=workspace:GetServerTimeNow()
 if serverNow<s.nextAt then s.hold=nil; count("CooldownRejections"); return end
 local h=s.hold
 if not h or h.site~=site or now-h.started<HOLD_SECONDS or now-h.started>1.85 or (h.endedAt and now-h.endedAt>0.12) then
  s.hold=nil; count("TimingRejections"); return
 end
 if not access:Invoke(player,site.zone) then s.hold=nil; count("AccessRejections"); return end
 if not validCharacter(player,h.character,site) then s.hold=nil; count("DistanceCancels"); return end
 local trained=strength(player)
 if sessions[player]~=s or s.hold~=h or not validCharacter(player,h.character,site) then s.hold=nil; return end
 s.hold=nil
 if site.legend then startRitual(player,s,site); return end
 s.nextAt=workspace:GetServerTimeNow()+COOLDOWN
 local speciesId=Catalog.Roll(site.zone,rng:NextNumber())
 local record,first,autoEquip,currentPower=award(player,s,speciesId,trained,false,site.zone)
 feedback(player,s,record,first,autoEquip,currentPower,false)
end
prompt.Triggered:Connect(function(player)
 local token=beginGrowth:Invoke(player); if not token then return end
 local ok,err=xpcall(function() captureTriggered(player) end,debug.traceback)
 endGrowth:Invoke(player,token); if not ok then warn(err) end
end)
end -- site bindings
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt
 if elapsed<0.05 then return end
 elapsed=0
 for player,s in pairs(sessions) do
  local h=s.hold
  if h and not validCharacter(player,h.character,h.site) then
   s.hold=nil
   count("DistanceCancels")
   resultEvent:FireClient(player,{kind="Canceled",reason="Distance"})
  elseif h and os.clock()-h.started>1.85 then
   s.hold=nil
   count("CanceledHolds")
  end
 end
end)
