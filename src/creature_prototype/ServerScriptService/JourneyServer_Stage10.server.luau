-- Server-observed, session-only journey facts and read-only timing journal.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local states={}
local function init(p)
 if states[p] then return end
 states[p]={started=workspace:GetServerTimeNow(),metrics={training=0,moving=0,holding=0,cooldown=0,battle=0,ritual=0,active=0},marks={}}
 p:SetAttribute("JourneyActive",true); p:SetAttribute("JourneyComplete",false)
end
Players.PlayerAdded:Connect(init); Players.PlayerRemoving:Connect(function(p) states[p]=nil end)
for _,p in ipairs(Players:GetPlayers()) do init(p) end
local function mark(p,s,key,attribute)
 if s.marks[key] then return end
 local t=workspace:GetServerTimeNow()-s.started
 local row=table.clone(s.metrics); row.elapsed=t; row.idle=math.max(0,t-row.active)
 s.marks[key]=row
 if attribute then p:SetAttribute(attribute,true) end
end
local read=Instance.new("BindableFunction"); read.Name="ReadJourney"; read.Parent=script
read.OnInvoke=function(p)
 local s=states[p]; if not s then return nil end
 local m=table.clone(s.metrics); m.elapsed=workspace:GetServerTimeNow()-s.started; m.idle=math.max(0,m.elapsed-m.active)
 local marks={}; for k,v in pairs(s.marks) do marks[k]=table.clone(v) end
 return {startedAt=s.started,metrics=m,milestones=marks}
end
local elapsed=0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt; if elapsed<.1 then return end; local step=elapsed; elapsed=0
 local cap=game.ServerScriptService:FindFirstChild("SeaCaptureServer_Stage2"); local activity=cap and cap:FindFirstChild("GetActivity_Stage10")
 local hub=workspace:FindFirstChild("CentralHub_Stage5"); local arena=hub and hub:FindFirstChild("Stage4_Exhibition")
 for p,s in pairs(states) do
  local mode=p:GetAttribute("TrainingMode") or ""
  local training=mode=="Speed" or mode=="Strength"
  local holding=false
  if activity then local a=activity:Invoke(p); holding=a and a.holding or false end
  local ritual=p:GetAttribute("SeaDragonRitual")==true
  local cooldown=(p:GetAttribute("SeaCooldownUntil") or 0)>workspace:GetServerTimeNow()
  local battle=arena and arena:GetAttribute("Busy") and arena:GetAttribute("ChallengerUserId")==p.UserId or false
  local c=p.Character; local r=c and c:FindFirstChild("HumanoidRootPart"); local h=c and c:FindFirstChildOfClass("Humanoid")
  local moving=false
  if r and h and h.Health>0 then
   if s.character==c and s.position then
    local d=Vector2.new(r.Position.X-s.position.X,r.Position.Z-s.position.Z).Magnitude
    moving=d>.04 and d<=h.WalkSpeed*step*2+1
   end
   s.character=c; s.position=r.Position
  else s.character=nil; s.position=nil end
  local statuses={training=training,moving=moving,holding=holding,cooldown=cooldown,battle=battle,ritual=ritual}
  local active=false
  for name,on in pairs(statuses) do if on then s.metrics[name]+=step; active=true end end
  if active then s.metrics.active+=step end
  if (p:GetAttribute("SeaCaptureCount") or 0)>0 then mark(p,s,"FirstCreature","JourneyHasCreature") end
  local speed=p:GetAttribute("SpeedTraining") or 0; local force=p:GetAttribute("StrengthTraining") or 0; local high=p:GetAttribute("HighestSpeedTraining") or 0
  if speed>0 then mark(p,s,"FirstSpeed","JourneyTriedSpeed") end
  if force>0 then mark(p,s,"FirstStrength","JourneyTriedStrength") end
  if speed>0 or force>0 then mark(p,s,"FirstTraining") end
  if p:GetAttribute("ArenaFirstBattleDone") then mark(p,s,"FirstChallenge","JourneyDidBattle") end
  if (p:GetAttribute("RebirthCount") or 0)>0 then mark(p,s,"FirstRebirth","JourneyDidRebirth") end
  if high>=150 then mark(p,s,"FarUnlocked") end
  if r and high>=50 and (r.Position-Vector3.new(242,13.2,48)).Magnitude<=14 then mark(p,s,"CoralVisit","JourneyVisitedCoral") end
  if r and high>=150 and (r.Position-Vector3.new(340,13.2,48)).Magnitude<=14 then mark(p,s,"FarVisit","JourneyVisitedFar") end
  if (p:GetAttribute("SeaDragonTraces") or 0)>=20 then mark(p,s,"TracesReady") end
  local folder=p:FindFirstChild("SeaCreatures_Stage3")
  local id=p:GetAttribute("SeaEquippedId")
  if folder then
   for _,e in ipairs(folder:GetChildren()) do if e:GetAttribute("SpeciesId")=="sea_dragon" then
    mark(p,s,"FirstDragon","JourneyHasDragon")
    if e.Name==id then mark(p,s,"DragonEquipped") end
   end end
  end
  if p:GetAttribute("ArenaDragonBattleDone") then
   mark(p,s,"JourneyComplete")
   p:SetAttribute("JourneyComplete",true); p:SetAttribute("JourneyActive",false)
  end
 end
end)
