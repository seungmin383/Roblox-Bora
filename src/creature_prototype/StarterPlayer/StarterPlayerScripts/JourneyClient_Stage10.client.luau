local p=game.Players.LocalPlayer
local sea=workspace:WaitForChild("SeaRegion_Stage1")
local hub=workspace:WaitForChild("CentralHub_Stage5")
local gui=Instance.new("BillboardGui"); gui.Name="JourneyMarker_Stage10"; gui.ResetOnSpawn=false; gui.Parent=p:WaitForChild("PlayerGui")
local column=Instance.new("Part"); column.Name="PersonalDestination_Stage10"; column.Size=Vector3.new(.3,8,.3); column.Anchored=true; column.CanCollide=false; column.CanTouch=false; column.CanQuery=false; column.Material=Enum.Material.Neon; column.Color=Color3.fromRGB(112,244,213); column.Parent=workspace
local tag=gui; tag.Adornee=column; tag.Size=UDim2.fromOffset(180,42); tag.StudsOffset=Vector3.new(0,5,0); tag.AlwaysOnTop=true; tag.MaxDistance=500; tag.Parent=p.PlayerGui
local label=Instance.new("TextLabel"); label.Size=UDim2.fromScale(1,1); label.BackgroundColor3=Color3.fromRGB(18,54,65); label.BackgroundTransparency=.12; label.TextColor3=Color3.fromRGB(154,255,225); label.Font=Enum.Font.GothamMedium; label.TextSize=16; label.Parent=tag
local function seaRoute(pos,target,name)
 if pos.X<56 then return Vector3.new(56,2,0),"바다 입구" end
 if pos.X<95 then return Vector3.new(98,13,0),"해변으로 가는 길" end
 if pos.X<166 or math.abs(pos.Z-48)>13 and pos.X<210 then return Vector3.new(170,12,48),"해변 채집 지점" end
 return target,name
end
local function hubRoute(pos,target,name)
 if pos.X>300 and pos.Z<40 then
  if pos.X<327 then return Vector3.new(331,12,18),"암초 사이 길" end
  return Vector3.new(331,12,48),"먼바다 발판" 
 end
 if pos.X>180 then return Vector3.new(170,12,48),"해변으로 돌아가기" end
 if pos.X>96 then return Vector3.new(96,13,0),"중앙으로 가는 길" end
 if pos.X>60 then return Vector3.new(56,2,0),"중앙 바다 입구" end
 return target,name
end
local function goal(pos)
 local speed=p:GetAttribute("SpeedTraining") or 0; local force=p:GetAttribute("StrengthTraining") or 0; local high=p:GetAttribute("HighestSpeedTraining") or 0
 local speedPos=Vector3.new(29,1,-27); local forcePos=Vector3.new(-31,1,-24); local arenaPos=Vector3.new(-19,2,10)
 local function seaGoal(text,target,name) local t,n=seaRoute(pos,target,name); return text,t,n end
 local function hubGoal(text,target,name) local t,n=hubRoute(pos,target,name); return text,t,n end
 if p:GetAttribute("JourneyComplete") then return "체험 완료 · 원하는 개체로 대표에 도전해 보세요" end
 if not p:GetAttribute("JourneyHasCreature") then return seaGoal("빛기둥을 따라 해변에서 첫 생물을 찾으세요 · 1초 누르기",Vector3.new(170,13,48),"첫 생물 찾기") end
 if not p:GetAttribute("JourneyTriedSpeed") then return hubGoal("속도 훈련 기구에 올라가 보세요",speedPos,"속도 훈련") end
 if not p:GetAttribute("JourneyTriedStrength") then return hubGoal("힘 훈련 기구에 올라가 보세요",forcePos,"힘 훈련") end
 if not p:GetAttribute("JourneyDidBattle") then return hubGoal("생물을 장착하고 중앙 전시대에 도전하세요",arenaPos,"첫 전시대 도전") end
 if not p:GetAttribute("JourneyVisitedCoral") then
  if high<50 then return hubGoal(string.format("산호 구역을 열도록 속도 50까지 훈련하세요 · 현재 %.1f",speed),speedPos,"속도 훈련") end
  return seaGoal("열린 산호 구역에 가보세요",Vector3.new(242,13,48),"산호 구역")
 end
 if not p:GetAttribute("JourneyDidRebirth") then
  if speed<100 then return hubGoal(string.format("첫 환생 준비 · 속도 100까지 훈련하세요 · 현재 %.1f",speed),speedPos,"속도 훈련") end
  if force<100 then return hubGoal(string.format("첫 환생 준비 · 힘 100까지 훈련하세요 · 현재 %.1f",force),forcePos,"힘 훈련") end
  return "환생 버튼을 열고 첫 환생을 해보세요"
 end
 if high<150 then return hubGoal(string.format("먼바다 준비 · 속도 최고 기록 150 달성 · 현재 %.1f / 최고 %.1f",speed,high),speedPos,"속도 훈련") end
 if not p:GetAttribute("JourneyVisitedFar") then return seaGoal("열린 먼바다 채집 지점에 가보세요",Vector3.new(340,13,48),"먼바다") end
 if not p:GetAttribute("JourneyHasDragon") then
  local traces=p:GetAttribute("SeaDragonTraces") or 0
  if traces<20 then return seaGoal(string.format("먼바다에서 일반 생물을 찾아 흔적을 모으세요 · %d/20",traces),Vector3.new(340,13,48),"해신룡 흔적 모으기") end
  if pos.Z>=40 and math.abs(pos.X-331)>4 then return "빛나는 암초 고리에서 해신룡을 깨우세요",Vector3.new(331,12,48),"암초 고리 입구" end
  if pos.Z>23 then return "빛나는 암초 고리에서 해신룡을 깨우세요",Vector3.new(331,12,18),"암초 사이 길" end
  return "깨우기 버튼을 1초 눌러 해신룡을 만나세요",Vector3.new(320,13,18),"해신룡 깨우기"
 end
 local folder=p:FindFirstChild("SeaCreatures_Stage3"); local selected=folder and folder:FindFirstChild(p:GetAttribute("SeaEquippedId") or "")
 if not selected or selected:GetAttribute("SpeciesId")~="sea_dragon" then return "보관함에서 해신룡을 장착하세요" end
 return hubGoal("해신룡을 들고 중앙 전시대에 도전하세요",arenaPos,"해신룡 전시대 도전")
end
local elapsed=0
game:GetService("RunService").RenderStepped:Connect(function(dt)
 elapsed+=dt; if elapsed<.1 then return end; elapsed=0
 local r=p.Character and p.Character:FindFirstChild("HumanoidRootPart")
 if not r then tag.Enabled=false; column.Transparency=1; return end
 local text,target,name=goal(r.Position)
 p:SetAttribute("JourneyText","지금 할 일 · "..text)
 local capture=p.PlayerGui:FindFirstChild("SeaCaptureHUD"); local toast=capture and capture:FindFirstChild("CaptureToast")
 local focused=p:GetAttribute("SeaInventoryOpen") or (p:GetAttribute("RebirthPanelOpen") or p:GetAttribute("TrainingUpgradeOpen")) or p:GetAttribute("SeaBattleUI") or p:GetAttribute("SeaLegendRewardOpen") or p:GetAttribute("SeaDragonRitual") or toast and toast.Visible
 local enabled=target~=nil and not focused and not p:GetAttribute("JourneyComplete")
 tag.Enabled=enabled; column.Transparency=enabled and .35 or 1
 if target then column.Position=target+Vector3.new(0,4,0); label.Text="▼ "..name end
end)
