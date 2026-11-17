local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local CAS=game:GetService("ContextActionService")
local player=Players.LocalPlayer
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local Growth=require(game.ReplicatedStorage:WaitForChild("TrainingRules_Stage6"))
local root=workspace:WaitForChild("CentralHub_Stage5"):WaitForChild("Stage4_Exhibition")
local prompt=root:WaitForChild("ChallengeAnchor"):WaitForChild("Challenge")
local event=game.ReplicatedStorage:WaitForChild("SeaBattle_Stage4"):WaitForChild("BattleEvent")
local gui=Instance.new("ScreenGui"); gui.Name="SeaBattleHUD_Stage4"; gui.ResetOnSpawn=false; gui.DisplayOrder=25; gui.Parent=player:WaitForChild("PlayerGui")
local panel=Instance.new("Frame"); panel.Name="Panel"; panel.AnchorPoint=Vector2.new(.5,1); panel.Position=UDim2.new(.5,0,1,-16); panel.Size=UDim2.new(.92,0,0,180); panel.BackgroundColor3=Color3.fromRGB(18,39,53); panel.BackgroundTransparency=.05; panel.BorderSizePixel=0; panel.Parent=gui; panel.Visible=false
local max=Instance.new("UISizeConstraint"); max.MaxSize=Vector2.new(660,184); max.Parent=panel
local label=Instance.new("TextLabel"); label.Name="Preview"; label.Position=UDim2.fromOffset(12,8); label.Size=UDim2.new(1,-24,0,108); label.BackgroundTransparency=1; label.TextColor3=Color3.fromRGB(245,246,230); label.TextSize=15; label.Font=Enum.Font.GothamMedium; label.TextWrapped=true; label.TextXAlignment=Enum.TextXAlignment.Left; label.Parent=panel
local button=Instance.new("TextButton"); button.Name="ChallengeButton"; button.Position=UDim2.new(.5,0,1,-60); button.AnchorPoint=Vector2.new(.5,0); button.Size=UDim2.fromOffset(280,52); button.BackgroundColor3=Color3.fromRGB(37,113,112); button.TextColor3=Color3.new(1,1,1); button.TextSize=17; button.Font=Enum.Font.GothamMedium; button.Parent=panel
button.TextScaled=true
local buttonCap=Instance.new("UITextSizeConstraint"); buttonCap.MinTextSize=12; buttonCap.MaxTextSize=17; buttonCap.Parent=button
local function layout()
 local compact=workspace.CurrentCamera.ViewportSize.Y<480
 panel.Position=UDim2.new(.5,0,1,-(compact and UIS.TouchEnabled and 16 or 90))
 panel.Size=UDim2.new(.92,0,0,compact and 156 or 184)
 label.Size=UDim2.new(1,-24,0,compact and 80 or 108)
end
layout()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
UIS:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)
local near=false; local resultText=nil; local resultUntil=0
local beats={["돌파"]="수호",["수호"]="기습",["기습"]="돌파"}
local function sameIndividual()
 return root:GetAttribute("ChampionOwnerId")==player.UserId and root:GetAttribute("ChampionId")==player:GetAttribute("SeaEquippedId")
end
local function challenge()
 if not sameIndividual() and near and not root:GetAttribute("Busy") and not player:GetAttribute("SeaInventoryOpen") and not (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen")) and not player:GetAttribute("SeaLegendRewardOpen") then prompt:InputHoldBegin(); prompt:InputHoldEnd() end
end
button.Activated:Connect(challenge)
CAS:BindActionAtPriority("ExhibitionChallenge_Stage4",function(_,state)
 if not near or UIS:GetFocusedTextBox() or player:GetAttribute("SeaInventoryOpen") or (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen")) or player:GetAttribute("SeaLegendRewardOpen") then return Enum.ContextActionResult.Pass end
 if state==Enum.UserInputState.Begin then challenge() end
 return Enum.ContextActionResult.Sink
end,false,Enum.ContextActionPriority.High.Value+10,Enum.KeyCode.E,Enum.KeyCode.ButtonX)
prompt.PromptShown:Connect(function() near=true end)
prompt.PromptHidden:Connect(function() near=false end)
event.OnClientEvent:Connect(function(data)
 resultUntil=os.clock()+7
 if data.kind=="Result" then
  resultText=string.format("%s\n내 현재 %d · 상성 +%d%% · 기세 +%.1f%% → %.1f\n상대 전시 %d · 상성 +%d%% · 기세 +%.1f%% → %.1f",data.replacement and (data.winner=="Challenger" and "대표 교체 성공 · 기록/보상 증가 없음" or "기존 대표 유지 · 기록/보상 증가 없음") or (data.winner=="Challenger" and "승리! 내 개체가 새 챔피언입니다" or "패배 · 내 생물은 그대로 보관됩니다"),data.aBase,math.round(data.aAdvantage*100),data.aMomentum*100,data.aFinal,data.bBase,math.round(data.bAdvantage*100),data.bMomentum*100,data.bFinal)
 else resultText=data.text end
end)
local elapsed=0
game:GetService("RunService").RenderStepped:Connect(function(dt)
 elapsed+=dt; if elapsed<.1 then return end; elapsed=0
 local fighting=root:GetAttribute("Busy") and root:GetAttribute("ChallengerUserId")==player.UserId
 local visible=near or fighting or os.clock()<resultUntil
 panel.Visible=visible and not player:GetAttribute("SeaInventoryOpen") and not (player:GetAttribute("RebirthPanelOpen") or player:GetAttribute("TrainingUpgradeOpen")) and not player:GetAttribute("SeaLegendRewardOpen"); player:SetAttribute("SeaBattleUI",panel.Visible)
 button.Visible=near and not root:GetAttribute("Busy") and os.clock()>=resultUntil
 local replacement=root:GetAttribute("ChampionOwnerId")==player.UserId
 local same=sameIndividual()
 button.Text=same and "현재 대표와 다른 개체를 장착하세요" or (UIS.TouchEnabled and "" or "[E] ")..(replacement and "대표 교체전" or "전시대 도전")
 button.Active=not same; button.AutoButtonColor=not same
 button.BackgroundColor3=same and Color3.fromRGB(75,90,96) or Color3.fromRGB(37,113,112)
 if fighting then label.Text=(root:GetAttribute("BattleMode")=="Replacement" and "대표 교체전 · " or "자동 전투 · ")..tostring(root:GetAttribute("Phase")).."\n"..(root:GetAttribute("BattleMode")=="Replacement" and "승리·방어 기록과 보상은 늘어나지 않습니다" or "양쪽 기세는 이번 전투 동안 고정됩니다")
 elseif os.clock()<resultUntil and resultText then label.Text=resultText
 else
  local own; local f=player:FindFirstChild("SeaCreatures_Stage3"); local id=player:GetAttribute("SeaEquippedId")
  own=f and id and f:FindFirstChild(id)
  local trait=own and own:GetAttribute("Trait"); local other=root:GetAttribute("ChampionTrait")
  local edge=trait and (beats[trait]==other and "내 생물 상성 우위 +15%" or (beats[other]==trait and "상대 상성 우위 +15%" or "상성 중립")) or "내 생물에서 개체를 장착하세요"
  label.Text=string.format("상대 %s · %.2f배 · %s · 전시 당시 %d\n내 생물 %s\n%s · 상대 방어 %d회",root:GetAttribute("ChampionName") or "산호게",root:GetAttribute("ChampionScale") or 0,other or "",root:GetAttribute("ChampionPower") or 0,own and string.format("%s · %.2f배 · %s · 현재 %d",Catalog.Get(own:GetAttribute("SpeciesId")).Name,own:GetAttribute("SizeScale"),trait,Growth.Power(own:GetAttribute("SizeScale"),player:GetAttribute("StrengthTraining") or 0,own:GetAttribute("SpeciesId"))) or "미장착",(replacement and "교체전 · 기록/보상 증가 없음" or edge),root:GetAttribute("Defenses") or 0)
 end
end)
