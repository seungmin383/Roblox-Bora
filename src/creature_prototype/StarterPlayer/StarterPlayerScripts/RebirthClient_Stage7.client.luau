local player=game.Players.LocalPlayer
local Growth=require(game.ReplicatedStorage:WaitForChild("TrainingRules_Stage6"))
local remotes=game.ReplicatedStorage:WaitForChild("Rebirth_Stage7")
local gui=Instance.new("ScreenGui"); gui.Name="RebirthHUD_Stage7"; gui.ResetOnSpawn=false; gui.DisplayOrder=40; gui.Parent=player:WaitForChild("PlayerGui")
local function button(name,parent,text,size,pos)
 local b=Instance.new("TextButton"); b.Name=name; b.Size=size; b.Position=pos; b.Text=text; b.Font=Enum.Font.GothamMedium; b.TextSize=16; b.BackgroundColor3=Color3.fromRGB(40,110,107); b.TextColor3=Color3.fromRGB(246,249,233); b.BorderSizePixel=0; b.Parent=parent
 local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,10); c.Parent=b; return b
end
local toggle=button("OpenRebirth",gui,"환생 · 0회",UDim2.fromOffset(180,42),UDim2.fromOffset(16,116))
local shade=button("Shade",gui,"",UDim2.fromScale(1,1),UDim2.fromScale(0,0)); shade.BackgroundColor3=Color3.new(0,0,0); shade.BackgroundTransparency=.35; shade.Visible=false
local panel=Instance.new("Frame"); panel.Name="Panel"; panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5); panel.Size=UDim2.fromScale(.92,.9); panel.BackgroundColor3=Color3.fromRGB(17,41,54); panel.BorderSizePixel=0; panel.Parent=shade
local max=Instance.new("UISizeConstraint"); max.MaxSize=Vector2.new(520,330); max.Parent=panel
local function label(name,pos,size,font)
 local t=Instance.new("TextLabel"); t.Name=name; t.Position=pos; t.Size=size; t.BackgroundTransparency=1; t.TextColor3=Color3.fromRGB(242,247,234); t.Font=Enum.Font.GothamMedium; t.TextSize=font; t.TextWrapped=true; t.TextXAlignment=Enum.TextXAlignment.Left; t.TextYAlignment=Enum.TextYAlignment.Top; t.Parent=panel; return t
end
local header=label("Header",UDim2.fromOffset(14,12),UDim2.new(1,-160,0,52),18)
local body=label("Conditions",UDim2.fromOffset(14,70),UDim2.new(1,-28,1,-186),15)
local status=label("Status",UDim2.new(0,14,1,-108),UDim2.new(1,-28,0,32),14); status.TextColor3=Color3.fromRGB(248,204,139)
local close=button("Close",panel,"닫기",UDim2.fromOffset(128,52),UDim2.new(1,-140,0,8))
local execute=button("Execute",panel,"환생하기",UDim2.new(1,-28,0,52),UDim2.new(0,14,1,-66))
body.TextScaled=true
local bodyCap=Instance.new("UITextSizeConstraint"); bodyCap.MinTextSize=12; bodyCap.MaxTextSize=15; bodyCap.Parent=body
local message=""; local messageUntil=0
local function open(value)
 shade.Visible=value; gui.DisplayOrder=value and 70 or 40; player:SetAttribute("RebirthPanelOpen",value)
 if value then local inv=player.PlayerGui:FindFirstChild("SeaInventoryHUD"); if inv then inv.ModalShade.Visible=false end; player:SetAttribute("SeaInventoryOpen",false) end
end
toggle.Activated:Connect(function() open(not shade.Visible) end)
close.Activated:Connect(function() open(false) end)
shade.Activated:Connect(function() open(false) end)
execute.Activated:Connect(function() remotes.Request:FireServer() end)
remotes.Result.OnClientEvent:Connect(function(data) message=data.text; messageUntil=os.clock()+4 end)
local elapsed=0
game:GetService("RunService").RenderStepped:Connect(function(dt)
 elapsed+=dt; if elapsed<.1 then return end; elapsed=0
 local r=player:GetAttribute("RebirthCount") or 0; local required=Growth.Requirement(r)
 local speed=player:GetAttribute("SpeedTraining") or 0; local force=player:GetAttribute("StrengthTraining") or 0
 toggle.Visible=not player:GetAttribute("TrainingUpgradeOpen")
 toggle.Text="환생 · "..r.."회"; header.Text=string.format("환생 %d회 · 훈련 %.1f배",r,Growth.Multiplier(r))
 body.Text=string.format("속도 %.1f / %d  ·  부족 %.1f\n힘 %.1f / %d  ·  부족 %.1f\n다음 훈련 배율 %.1f배\n\n속도와 힘은 0으로\n생물·코인·장비·장착은 유지",speed,required,math.max(0,required-speed),force,required,math.max(0,required-force),Growth.Multiplier(r+1))
 local arena=workspace:FindFirstChild("CentralHub_Stage5"); arena=arena and arena:FindFirstChild("Stage4_Exhibition")
 local busy=arena and arena:GetAttribute("Busy") and arena:GetAttribute("ChallengerUserId")==player.UserId
 local ready=speed>=required and force>=required and not busy
 execute.BackgroundColor3=ready and Color3.fromRGB(40,128,112) or Color3.fromRGB(88,98,107)
 if os.clock()<messageUntil then status.Text=message
 elseif busy then status.Text="전투가 끝난 뒤 환생할 수 있어요"
 elseif not ready then status.Text="부족한 훈련치를 먼저 모아주세요"
 else status.Text="조건 충족 · 속도와 힘을 초기화합니다" end
end)
