local Players=game:GetService("Players")
local player=Players.LocalPlayer
local gui=Instance.new("ScreenGui"); gui.Name="TrainingHUD_Stage6"; gui.ResetOnSpawn=false; gui.DisplayOrder=15; gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame"); panel.Name="Stats"; panel.BackgroundColor3=Color3.fromRGB(18,43,55); panel.BackgroundTransparency=.1; panel.BorderSizePixel=0; panel.Parent=gui
local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,10); corner.Parent=panel
local stats=Instance.new("TextLabel"); stats.Name="Values"; stats.Position=UDim2.fromOffset(12,6); stats.Size=UDim2.new(1,-24,0,40); stats.TextColor3=Color3.fromRGB(244,247,233); stats.BackgroundTransparency=1; stats.TextXAlignment=Enum.TextXAlignment.Left; stats.TextSize=14; stats.Font=Enum.Font.GothamMedium; stats.Parent=panel
local feedback=stats:Clone(); feedback.Name="Feedback"; feedback.Position=UDim2.fromOffset(12,46); feedback.Size=UDim2.new(1,-24,0,22); feedback.TextColor3=Color3.fromRGB(120,240,207); feedback.TextSize=13; feedback.Parent=panel
local nearUpgrade=false
stats.TextScaled=true
local statLimit=Instance.new("UITextSizeConstraint"); statLimit.MinTextSize=11; statLimit.MaxTextSize=14; statLimit.Parent=stats
local lastGain=0
player:GetAttributeChangedSignal("TrainingTickSerial"):Connect(function() lastGain=os.clock() end)
local function layout()
 local w=workspace.CurrentCamera.ViewportSize.X
 if w<650 then panel.AnchorPoint=Vector2.zero; panel.Position=UDim2.fromOffset(16,164); panel.Size=UDim2.new(1,-32,0,nearUpgrade and 120 or 72)
 else panel.AnchorPoint=Vector2.new(1,0); panel.Position=UDim2.new(1,-16,0,16); panel.Size=UDim2.fromOffset(330,nearUpgrade and 120 or 72) end
end
layout(); workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
local root=workspace:WaitForChild("CentralHub_Stage5"):WaitForChild("Stage6_Training")
local speed=root:WaitForChild("SpeedTreadmill"); local strength=root:WaitForChild("StrengthMachine")
local stripes={}; for _,p in ipairs(speed:GetChildren()) do if string.find(p.Name,"BeltStripe") then table.insert(stripes,{part=p,index=p:GetAttribute("StripeIndex")}) end end
local weight=strength:WaitForChild("AnimatedWeight"); local weightStart=weight.CFrame
local billboards={}
local function track(obj) if obj:IsA("BillboardGui") then billboards[obj]=obj.Enabled end end
for _,obj in ipairs(workspace:GetDescendants()) do track(obj) end
workspace.DescendantAdded:Connect(track)
local function focusWorldLabels(focused)
 for obj,wasEnabled in pairs(billboards) do
  if obj.Parent then obj.Enabled=wasEnabled and not focused else billboards[obj]=nil end
 end
end

local Http=game:GetService("HttpService")
local Equipment=require(game.ReplicatedStorage:WaitForChild("TrainingEquipmentRules_Stage11"))
local Growth=require(game.ReplicatedStorage:WaitForChild("TrainingRules_Stage6"))
local upgrades=game.ReplicatedStorage:WaitForChild("TrainingUpgrade_Stage11")
local function makeButton(name,parent,text,size,pos)
 local v=Instance.new("TextButton"); v.Name=name; v.Parent=parent; v.Size=size; v.Position=pos; v.Text=text
 v.Font=Enum.Font.GothamMedium; v.TextSize=15; v.TextColor3=Color3.fromRGB(245,251,240); v.BackgroundColor3=Color3.fromRGB(32,111,105); v.BorderSizePixel=0
 local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,9); c.Parent=v; return v
end
local openUpgrade=makeButton("OpenUpgrade",panel,"훈련 장비 강화",UDim2.new(1,-24,0,40),UDim2.fromOffset(12,74)); openUpgrade.Visible=false
local modal=Instance.new("ScreenGui"); modal.Name="TrainingUpgradeHUD_Stage11"; modal.DisplayOrder=80; modal.ResetOnSpawn=false; modal.Parent=player.PlayerGui
local shade=makeButton("Shade",modal,"",UDim2.fromScale(1,1),UDim2.fromScale(0,0)); shade.BackgroundColor3=Color3.new(0,0,0); shade.BackgroundTransparency=.3; shade.AutoButtonColor=false; shade.Visible=false
local box=Instance.new("Frame"); box.Name="Panel"; box.Size=UDim2.new(.92,0,0,294); box.AnchorPoint=Vector2.new(.5,.5); box.Position=UDim2.fromScale(.5,.5); box.BackgroundColor3=Color3.fromRGB(17,43,54); box.BorderSizePixel=0; box.Parent=shade
local max=Instance.new("UISizeConstraint"); max.MaxSize=Vector2.new(440,294); max.Parent=box
local bc=Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,12); bc.Parent=box
local function text(name,y,height,size)
 local v=Instance.new("TextLabel"); v.Name=name; v.Parent=box; v.Position=UDim2.fromOffset(14,y); v.Size=UDim2.new(1,-28,0,height); v.BackgroundTransparency=1; v.Font=Enum.Font.GothamMedium; v.TextColor3=Color3.fromRGB(243,249,236); v.TextXAlignment=Enum.TextXAlignment.Left; v.TextYAlignment=Enum.TextYAlignment.Top; v.TextWrapped=true; v.TextSize=size; return v
end
local heading=text("Heading",14,40,18); heading.Text="훈련 장비 강화"; heading.Size=UDim2.new(1,-146,0,40)
local close=makeButton("Close",box,"닫기",UDim2.fromOffset(108,44),UDim2.new(1,-122,0,8))
local current=text("Current",62,52,16)
local nextInfo=text("Next",118,49,16)
local status=text("Status",176,40,14); status.TextColor3=Color3.fromRGB(255,214,151)
local buy=makeButton("Buy",box,"구매",UDim2.new(1,-28,0,50),UDim2.fromOffset(14,230))
local displayedVersion=nil
local pending=false; local pendingAt=0; local message=""; local messageUntil=0; local coolUntil=0
local function view()
 local raw=player:GetAttribute("TrainingEquipmentState")
 local ok,s=pcall(Http.JSONDecode,Http,raw or "")
 if not ok or type(s)~="table" then return nil end
 if not Equipment.Multipliers[s.level] or type(s.coins)~="number" or type(s.version)~="number" then return nil end
 return s
end
local function setOpen(value)
 if value and (not nearUpgrade or player:GetAttribute("SeaInventoryOpen") or player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("SeaBattleUI") or player:GetAttribute("SeaLegendRewardOpen")) then return end
 shade.Visible=value; player:SetAttribute("TrainingUpgradeOpen",value)
end
openUpgrade.Activated:Connect(function() message=""; messageUntil=0; setOpen(true) end)
close.Activated:Connect(function() setOpen(false) end)
shade.Activated:Connect(function() setOpen(false) end)
buy.Activated:Connect(function()
 local s=view()
 if not shade.Visible or pending or os.clock()<coolUntil or not s or s.level>=Equipment.MaxLevel or s.coins<(Equipment.Costs[s.level] or math.huge) then return end
 pending=true; pendingAt=os.clock(); coolUntil=os.clock()+.5
 upgrades.Request:FireServer(displayedVersion)
end)
upgrades.Result.OnClientEvent:Connect(function(data)
 pending=false; message=tostring(data.text or ""); messageUntil=os.clock()+3
end)
player.CharacterRemoving:Connect(function() setOpen(false) end)
local function updateUpgrade()
 local r=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
 local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
 local near=r~=nil and h~=nil and h.Health>0 and math.min((r.Position-speed.TrainingSurface.Position).Magnitude,(r.Position-strength.TrainingSurface.Position).Magnitude)<=16
 if nearUpgrade~=near then nearUpgrade=near; layout() end
 local focus=player:GetAttribute("SeaInventoryOpen") or player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("SeaBattleUI") or player:GetAttribute("SeaLegendRewardOpen") or player:GetAttribute("SeaDragonRitual")
 if shade.Visible and (not near or focus) then setOpen(false) end
 openUpgrade.Visible=near and not focus
 local s=view()
 if not s then current.Text="장비 정보를 준비 중이에요"; buy.Interactable=false; return end
 displayedVersion=s.version
 local rebirth=Growth.Multiplier(player:GetAttribute("RebirthCount") or 0)
 local gain=rebirth*Equipment.Multipliers[s.level]
 current.Text=string.format("장비 %d등급 · 코인 %d\n현재 초당 +%s  (환생 %s × 장비 %.2f)",s.level,s.coins,Equipment.Format(gain),Equipment.Format(rebirth),Equipment.Multipliers[s.level])
 local cost=Equipment.Costs[s.level]; local maxed=s.level>=Equipment.MaxLevel
 if maxed then
  nextInfo.Text="최대 등급 · 속도와 힘 훈련에 함께 적용"
  openUpgrade.Text="훈련 장비 · 최대 3등급"
 else
  nextInfo.Text=string.format("다음 %d등급 · 코인 %d\n구매 후 초당 +%s",s.level+1,cost,Equipment.Format(rebirth*Equipment.Multipliers[s.level+1]))
  openUpgrade.Text=s.coins>=cost and string.format("장비 강화 가능 · 코인 %d → %d등급",cost,s.level+1) or string.format("훈련 장비 강화 · 코인 %d 필요",cost)
 end
 if pending and os.clock()-pendingAt>5 then pending=false; message="응답을 기다리는 중이에요 · 현재 상태를 확인하세요"; messageUntil=os.clock()+3 end
 local ready=not maxed and s.coins>=cost and not pending and os.clock()>=coolUntil
 buy.Interactable=ready; buy.AutoButtonColor=ready; buy.BackgroundColor3=ready and Color3.fromRGB(32,125,109) or Color3.fromRGB(76,91,100)
 buy.Text=pending and "구매 처리 중…" or maxed and "최대 등급" or string.format("구매 · 코인 %d",cost)
 if os.clock()<messageUntil then status.Text=message
 elseif maxed then status.Text="추가 차감 없음 · 환생 후에도 장비 유지"
 elseif s.coins<cost then status.Text=string.format("코인 %d개 부족 · 생물 포획으로 모으세요",cost-s.coins)
 else status.Text="구매 즉시 적용 · 쌓인 훈련치는 그대로" end
end

local elapsed=0
game:GetService("RunService").RenderStepped:Connect(function(dt)
 local running=(speed:GetAttribute("ActiveUsers") or 0)>0
 for _,row in ipairs(stripes) do local z=-3.5+((row.index+(running and os.clock()*2 or 0))%8); row.part.CFrame=speed.TrainingSurface.CFrame*CFrame.new(0,.18,z) end
 if (strength:GetAttribute("ActiveUsers") or 0)>0 then weight.CFrame=weightStart+Vector3.new(0,math.sin(os.clock()*3)*.35,0) else weight.CFrame=weightStart end
 elapsed+=dt; if elapsed<.1 then return end; elapsed=0
 updateUpgrade()
 local capture=player.PlayerGui:FindFirstChild("SeaCaptureHUD")
 local toast=capture and capture:FindFirstChild("CaptureToast")
 panel.Visible=not player:GetAttribute("TrainingUpgradeOpen") and not player:GetAttribute("SeaBattleUI") and not player:GetAttribute("SeaLegendRewardOpen") and not player:GetAttribute("SeaInventoryOpen") and not player:GetAttribute("RebirthPanelOpen") and not (toast and toast.Visible)
 local modeNow=player:GetAttribute("TrainingMode") or ""
 focusWorldLabels(modeNow~="" or player:GetAttribute("SeaInventoryOpen")==true or player:GetAttribute("SeaBattleUI")==true or player:GetAttribute("RebirthPanelOpen")==true or player:GetAttribute("JourneyActive")==true or player:GetAttribute("TrainingUpgradeOpen")==true)
 local speedPoints=player:GetAttribute("SpeedTraining") or 0
 local force=player:GetAttribute("StrengthTraining") or 0
 stats.Text=string.format("속도 %s · 최고 %s · 이동 %s\n힘 %s · 장비 %d · 초당 +%s",Equipment.Format(speedPoints),Equipment.Format(player:GetAttribute("HighestSpeedTraining") or 0),Equipment.Format(player:GetAttribute("TrainingWalkSpeed") or 16),Equipment.Format(force),player:GetAttribute("TrainingEquipmentLevel") or 0,Equipment.Format(player:GetAttribute("TrainingGainPerSecond") or 1))
 local mode=player:GetAttribute("TrainingMode")
 if mode=="Speed" or mode=="Strength" then feedback.Text=(mode=="Speed" and "속도" or "힘").." 훈련 중 · 매초 +"..Equipment.Format(player:GetAttribute("TrainingGainPerSecond") or 1)
 else feedback.Text="" end
end)
