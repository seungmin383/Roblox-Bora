-- Stage 2 HUD and feedback; never grants rewards or changes collection state.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")
local ContextActionService=game:GetService("ContextActionService")
local player=Players.LocalPlayer
local shared=game:GetService("ReplicatedStorage"):WaitForChild("SeaCapture_Stage2")
local resultEvent=shared:WaitForChild("CaptureResult")
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local previews=game.ReplicatedStorage:WaitForChild("CreaturePreviews_Stage8")
local prompt=workspace:WaitForChild("SeaRegion_Stage1"):WaitForChild("Stage2_Collection"):WaitForChild("ActiveBeachSite"):WaitForChild("PromptAnchor"):WaitForChild("FindCreature")
local gui=Instance.new("ScreenGui")
gui.Name="SeaCaptureHUD"
gui.ResetOnSpawn=false
gui.DisplayOrder=10
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=player:WaitForChild("PlayerGui")
local function round(parent,pixels)
 local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,pixels); c.Parent=parent
end
local function frame(name,parent,size,pos)
 local f=Instance.new("Frame"); f.Name=name; f.Size=size; f.Position=pos
 f.BackgroundColor3=Color3.fromRGB(17,42,54); f.BackgroundTransparency=0.12; f.BorderSizePixel=0; f.Parent=parent; round(f,12); return f
end
local function label(name,parent,text,size,pos,textSize)
 local t=Instance.new("TextLabel"); t.Name=name; t.Size=size; t.Position=pos; t.Text=text; t.Font=Enum.Font.GothamMedium
 t.TextSize=textSize; t.TextColor3=Color3.fromRGB(244,247,235); t.BackgroundTransparency=1; t.TextXAlignment=Enum.TextXAlignment.Left; t.Parent=parent; return t
end
local stats=frame("Counters",gui,UDim2.fromOffset(238,42),UDim2.fromOffset(16,16))
local coins=label("Coins",stats,"코인  0",UDim2.new(.5,-12,1,0),UDim2.fromOffset(14,0),16)
local species=label("SpeciesCount",stats,"수집  0종",UDim2.new(.5,-8,1,0),UDim2.new(.5,4,0,0),16)
local hint=frame("NextAction",gui,UDim2.new(.9,0,0,48),UDim2.new(.5,0,1,-92)); hint.AnchorPoint=Vector2.new(.5,1)
local limit=Instance.new("UISizeConstraint"); limit.MaxSize=Vector2.new(640,48); limit.Parent=hint
local hintText=label("HintText",hint,"",UDim2.new(1,-24,1,-6),UDim2.fromOffset(12,0),16)
hintText.TextXAlignment=Enum.TextXAlignment.Center; hintText.TextScaled=true; hintText.TextWrapped=true
local textLimit=Instance.new("UITextSizeConstraint"); textLimit.MinTextSize=11; textLimit.MaxTextSize=16; textLimit.Parent=hintText
local track=frame("HoldProgress",hint,UDim2.new(1,-24,0,4),UDim2.new(0,12,1,-7)); track.Visible=false; track.BackgroundColor3=Color3.fromRGB(50,78,84)
local fill=frame("Fill",track,UDim2.fromScale(0,1),UDim2.fromScale(0,0)); fill.BackgroundColor3=Color3.fromRGB(112,240,208); fill.BackgroundTransparency=0
local action=Instance.new("TextButton")
action.Name="CaptureButton"; action.Size=UDim2.fromOffset(220,56); action.Position=UDim2.new(.5,0,1,-150); action.AnchorPoint=Vector2.new(.5,1)
action.BackgroundColor3=Color3.fromRGB(35,115,111); action.BackgroundTransparency=.05; action.BorderSizePixel=0
action.TextColor3=Color3.fromRGB(246,255,242); action.Font=Enum.Font.GothamMedium; action.TextSize=17
action.Text="생물 찾기 · 1초 누르기"; action.Visible=false; action.Parent=gui; round(action,12)
local toast=frame("CaptureToast",gui,UDim2.new(.9,0,0,132),UDim2.new(.5,0,.22,0)); toast.AnchorPoint=Vector2.new(.5,0); toast.Visible=false
local toastLimit=Instance.new("UISizeConstraint"); toastLimit.MaxSize=Vector2.new(440,132); toastLimit.Parent=toast
local viewport=Instance.new("ViewportFrame"); viewport.Name="CoralCrabPreview"; viewport.Size=UDim2.fromOffset(104,104); viewport.Position=UDim2.fromOffset(8,14); viewport.BackgroundTransparency=1
viewport.Ambient=Color3.fromRGB(210,221,235); viewport.LightColor=Color3.fromRGB(255,241,216); viewport.Parent=toast
local world=Instance.new("WorldModel"); world.Parent=viewport
local preview=shared:WaitForChild("CoralCrabPreview"):Clone(); preview.Parent=world
local camera=Instance.new("Camera"); camera.CFrame=CFrame.lookAt(Vector3.new(4,3,5),Vector3.new(0,.2,0)); camera.FieldOfView=35; camera.Parent=viewport; viewport.CurrentCamera=camera
local title=label("Title",toast,"",UDim2.new(1,-126,0,32),UDim2.fromOffset(118,18),18); title.TextWrapped=true; title.TextScaled=true
local titleLimit=Instance.new("UITextSizeConstraint"); titleLimit.MaxTextSize=18; titleLimit.MinTextSize=12; titleLimit.Parent=title
local name=label("CreatureName",toast,"산호게 · 일반",UDim2.new(1,-126,0,26),UDim2.fromOffset(118,53),17)
name.TextColor3=Color3.fromRGB(255,169,143)
local detail=label("Result",toast,"",UDim2.new(1,-126,0,34),UDim2.fromOffset(118,82),14); detail.TextWrapped=true
local function layoutToast()
 local cam=workspace.CurrentCamera
 local compact=cam.ViewportSize.Y<480
 local left=compact and 94 or 118
 toast.Size=UDim2.new(.9,0,0,compact and 96 or 132)
 toast.AnchorPoint=Vector2.new(.5,compact and 1 or 0)
 toast.Position=compact and UDim2.new(.5,0,1,-60) or UDim2.new(.5,0,.22,0)
 viewport.Size=UDim2.fromOffset(compact and 76 or 104,compact and 76 or 104)
 viewport.Position=UDim2.fromOffset(8,compact and 10 or 14)
 title.Position=UDim2.fromOffset(left,compact and 9 or 18)
 title.Size=UDim2.new(1,-left-8,0,32)
 titleLimit.MaxTextSize=compact and 16 or 18
 name.Position=UDim2.fromOffset(left,compact and 38 or 53)
 name.Size=UDim2.new(1,-left-8,0,compact and 22 or 26)
 name.TextSize=compact and 15 or 17
 detail.Position=UDim2.fromOffset(left,compact and 61 or 82)
 detail.Size=UDim2.new(1,-left-8,0,compact and 28 or 34)
 detail.TextSize=compact and 12 or 14
end
layoutToast()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutToast)
local prompts={}
local function canCapture()
 local id=prompts[prompt] or "beach"
 return not player:GetAttribute("SeaDragonRitual") and not player:GetAttribute("SeaLegendRewardOpen") and (prompt.Name~="AwakenSeaDragon" or (player:GetAttribute("SeaDragonTraces") or 0)>=20) and (player:GetAttribute("HighestSpeedTraining") or 0)>=Catalog.Zones[id].Required
end
local holding=false
local shown=false
local pointerInput
local keyHolding=false
local holdTween
local cooldownUntil=0
local toastVersion=0
local lastInput=UIS:GetLastInputType()
local function legacyGuidance()
 if player:GetAttribute("SeaDragonRitual") then return player.DisplayName.."의 해신룡 · "..tostring(player:GetAttribute("SeaDragonRitualPhase") or "해신룡이 깨어나는 중…").." · 멀어지면 취소" end
 local untilTime=player:GetAttribute("SeaAccessNoticeUntil") or 0
 if workspace:GetServerTimeNow()<untilTime then return player:GetAttribute("SeaAccessNotice") or "" end
 if player:GetAttribute("InCentralSafeZone") then return "동쪽 바다로 이동 · 산호 구역 최고 속도 50 / 먼바다 150" end
 local r=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
 if r and math.abs(r.Position.Z-48)<14 then
  for _,gate in ipairs({{x=210,id="coral"},{x=286,id="far"}}) do
   if math.abs(r.Position.X-gate.x)<22 then
    local z=Catalog.Zones[gate.id]; local h=player:GetAttribute("HighestSpeedTraining") or 0
    return string.format("%s · 최고 속도 %d 필요 / 내 최고 %.1f · %s",z.Name,z.Required,h,h>=z.Required and "해금 완료" or "잠김")
   end
  end
 end
 local id=shown and prompts[prompt] or player:GetAttribute("CurrentSeaZone")
 local z=Catalog.Zones[id or ""] or Catalog.Zones.beach
 local high=player:GetAttribute("HighestSpeedTraining") or 0
 if high<z.Required then return string.format("%s · 최고 속도 %d 필요 / 내 최고 %.1f",z.Name,z.Required,high) end
 local key=UIS.TouchEnabled and "‘찾기/깨우기’ 버튼" or string.find(lastInput.Name,"Gamepad") and "X" or "E"
 if id=="far" then
  local traces=player:GetAttribute("SeaDragonTraces") or 0
  local dragon=workspace.SeaRegion_Stage1:FindFirstChild("Stage9_Legend")
  if dragon and dragon:GetAttribute("RitualBusy") then return tostring(dragon:GetAttribute("RitualOwnerName")).."의 해신룡 등장 중 · 잠시 기다려 주세요" end
  if prompt.Name=="AwakenSeaDragon" and shown then return string.format("해신룡 흔적 %d/20 · %s",traces,traces>=20 and key.." 1초로 깨우기" or "먼바다 일반 포획 성공마다 +1") end
  return string.format("해신룡 흔적 %d/20 · %s",traces,traces>=20 and "빛나는 암초 고리에서 깨우세요" or "먼바다 포획 성공마다 +1 · "..key.." 1초")
 end
 return string.format("%s · %s 1초 누르기 · 최고 속도 %.1f",z.Name,key,high)
end
local function guidance()
 if player:GetAttribute("SeaDragonRitual") then return player.DisplayName.."의 해신룡 · "..tostring(player:GetAttribute("SeaDragonRitualPhase") or "깨우는 중").." · 멀어지면 취소" end
 if workspace:GetServerTimeNow()<(player:GetAttribute("SeaAccessNoticeUntil") or 0) then return player:GetAttribute("SeaAccessNotice") or "" end
 if player:GetAttribute("JourneyActive") or player:GetAttribute("JourneyComplete") and player:GetAttribute("InCentralSafeZone") then return player:GetAttribute("JourneyText") or "지금 할 일 · 동쪽 해변에서 첫 생물을 찾아보세요" end
 return legacyGuidance()
end
local function stopProgress()
 holding=false
 if holdTween then holdTween:Cancel(); holdTween=nil end
 fill.Size=UDim2.fromScale(0,1); track.Visible=false
end
local function counters()
 coins.Text="코인  "..tostring(player:GetAttribute("SeaCoins") or 0)
 species.Text="수집  "..tostring(player:GetAttribute("SeaSpeciesCount") or 0).."종"
end
player:GetAttributeChangedSignal("SeaCoins"):Connect(counters)
player:GetAttributeChangedSignal("SeaSpeciesCount"):Connect(counters)
player:GetAttributeChangedSignal("SeaCooldownUntil"):Connect(function() cooldownUntil=player:GetAttribute("SeaCooldownUntil") or 0 end)
cooldownUntil=player:GetAttribute("SeaCooldownUntil") or 0
counters()
UIS.LastInputTypeChanged:Connect(function(input) lastInput=input end)
action.InputBegan:Connect(function(input)
 if (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1) and action.Visible and canCapture() and prompt.Enabled and not pointerInput and not keyHolding then
  pointerInput=input
  prompt:InputHoldBegin()
 end
end)
UIS.InputEnded:Connect(function(input)
 if pointerInput and (input==pointerInput or (input.UserInputType==Enum.UserInputType.MouseButton1 and pointerInput.UserInputType==Enum.UserInputType.MouseButton1)) then
  pointerInput=nil
  prompt:InputHoldEnd()
 end
end)
local function captureKey(_,state)
 if state==Enum.UserInputState.Begin then
  if UIS:GetFocusedTextBox() or player:GetAttribute("SeaInventoryOpen") or (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen")) or not shown or not canCapture() or not prompt.Enabled then return Enum.ContextActionResult.Pass end
  if not keyHolding and not pointerInput then keyHolding=true; prompt:InputHoldBegin() end
  return Enum.ContextActionResult.Sink
 elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then
  if keyHolding then keyHolding=false; prompt:InputHoldEnd(); return Enum.ContextActionResult.Sink end
 end
 return Enum.ContextActionResult.Pass
end
ContextActionService:BindActionAtPriority("SeaCaptureHold_Stage2",captureKey,false,Enum.ContextActionPriority.High.Value+1,prompt.KeyboardKeyCode,prompt.GamepadKeyCode)
UIS.WindowFocusReleased:Connect(function()
 if pointerInput or keyHolding then pointerInput=nil; keyHolding=false; prompt:InputHoldEnd() end
 stopProgress()
end)
local function attach(point)
 if not point:IsA("ProximityPrompt") or (point.Name~="FindCreature" and point.Name~="AwakenSeaDragon") or prompts[point] then return end
 prompts[point]=point.Parent.Parent:GetAttribute("ZoneId") or "beach"
 point.PromptShown:Connect(function() prompt=point; shown=true end)
 point.PromptHidden:Connect(function()
  if prompt~=point then return end
  shown=false
  if pointerInput or keyHolding then pointerInput=nil; keyHolding=false; point:InputHoldEnd() end
  stopProgress()
 end)
 point.PromptButtonHoldBegan:Connect(function()
  if point~=prompt or cooldownUntil>workspace:GetServerTimeNow() or not canCapture() then return end
  stopProgress(); holding=true; track.Visible=true
  holdTween=TweenService:Create(fill,TweenInfo.new(point.HoldDuration,Enum.EasingStyle.Linear),{Size=UDim2.fromScale(1,1)}); holdTween:Play()
 end)
 point.PromptButtonHoldEnded:Connect(function() if point==prompt then stopProgress() end end)
 point.Triggered:Connect(function() if point==prompt then stopProgress() end end)
end
local sea=workspace:WaitForChild("SeaRegion_Stage1")
for _,v in ipairs(sea:GetDescendants()) do attach(v) end
sea.DescendantAdded:Connect(attach)
player.CharacterRemoving:Connect(function()
 if pointerInput or keyHolding then pointerInput=nil; keyHolding=false; prompt:InputHoldEnd() end
 stopProgress()
end)
resultEvent.OnClientEvent:Connect(function(result)
 stopProgress()
 if result.untilTime then cooldownUntil=result.untilTime end
 if result.legend then return end
 if result.kind=="New" or result.kind=="Individual" then
  toastVersion+=1; local version=toastVersion
  title.Text=result.kind=="New" and "새로운 생물 발견!" or "새 개체를 발견했어요!"
  name.Text=Catalog.Get(result.speciesId).Name
  preview:Destroy(); preview=previews[result.speciesId]:Clone(); preview:ScaleTo(result.scale); preview.Parent=world; preview:PivotTo(CFrame.identity)
  local cf,size=preview:GetBoundingBox(); camera.CFrame=CFrame.lookAt(cf.Position+Vector3.new(1,.65,1).Unit*math.max(size.Magnitude*1.4,4),cf.Position)
  detail.Text=string.format("%.2f배 · %s · 전투력 %d · 코인 +1",result.scale,result.trait,result.power)..((player:GetAttribute("CurrentSeaZone")=="far") and string.format(" · 흔적 %d/20",result.traces or 0) or "")
  toast.Visible=true
  task.delay(2.8,function() if version==toastVersion then toast.Visible=false end end)
 end
end)
local tickElapsed=0
RunService.RenderStepped:Connect(function(dt)
 tickElapsed+=dt; if tickElapsed<0.06 then return end; tickElapsed=0
 local remaining=math.max(0,cooldownUntil-workspace:GetServerTimeNow())
 hint.Visible=not player:GetAttribute("SeaInventoryOpen") and not player:GetAttribute("SeaLegendRewardOpen") and not toast.Visible and not (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen")) and not player:GetAttribute("SeaBattleUI")
 local ready=remaining<=0 and not player:GetAttribute("SeaDragonRitual") and not player:GetAttribute("SeaLegendRewardOpen")
 for point in pairs(prompts) do local enabled=ready and not (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen")); if point.Enabled~=enabled then point.Enabled=enabled end end
 action.Visible=shown and ready and canCapture() and not player:GetAttribute("SeaInventoryOpen") and not (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen"))
 local verb=prompt.Name=="AwakenSeaDragon" and "해신룡 깨우기" or "생물 찾기"
 local prefix=UIS.TouchEnabled and "" or string.find(lastInput.Name,"Gamepad") and "[X] " or "[E] "
 action.Text=holding and "누르고 있는 중…" or prefix..verb.." · 1초 누르기"
 if player:GetAttribute("SeaDragonRitual") then hintText.Text=guidance()
 elseif not ready then hintText.Text=string.format("%s · 다시 찾기 %.1f초",guidance(),remaining)
 elseif holding then hintText.Text="물결 속 생물을 찾는 중…"
 else hintText.Text=guidance() end
end)
