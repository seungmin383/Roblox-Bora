local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local p=Players.LocalPlayer
local root=workspace:WaitForChild("SeaRegion_Stage1"):WaitForChild("Stage9_Legend")
local Catalog=require(RS:WaitForChild("SpeciesCatalog_Stage8"))
local gui=Instance.new("ScreenGui"); gui.Name="SeaLegendReward_Stage9"; gui.DisplayOrder=65; gui.ResetOnSpawn=false; gui.Parent=p:WaitForChild("PlayerGui")
local shade=Instance.new("TextButton"); shade.Name="Shade"; shade.Size=UDim2.fromScale(1,1); shade.Text=""; shade.BackgroundColor3=Color3.new(0,0,0); shade.BackgroundTransparency=.4; shade.Visible=false; shade.AutoButtonColor=false; shade.Parent=gui
local panel=Instance.new("Frame"); panel.Name="Panel"; panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5); panel.Size=UDim2.fromScale(.92,.86); panel.BackgroundColor3=Color3.fromRGB(15,45,61); panel.BorderSizePixel=0; panel.Parent=shade
local cap=Instance.new("UISizeConstraint"); cap.MaxSize=Vector2.new(620,340); cap.Parent=panel
local function text(name,size,pos,fontSize)
 local l=Instance.new("TextLabel"); l.Name=name; l.Size=size; l.Position=pos; l.BackgroundTransparency=1; l.TextColor3=Color3.fromRGB(240,249,244); l.Font=Enum.Font.GothamMedium; l.TextSize=fontSize; l.TextWrapped=true; l.Parent=panel; return l
end
local title=text("Title",UDim2.new(1,-24,0,44),UDim2.fromOffset(12,6),21); title.Text="전설 발견 · 해신룡"
local viewport=Instance.new("ViewportFrame"); viewport.Name="SeaDragonPreview"; viewport.Size=UDim2.fromOffset(130,130); viewport.Position=UDim2.fromOffset(12,64); viewport.BackgroundTransparency=1; viewport.Ambient=Color3.fromRGB(210,235,255); viewport.Parent=panel
local world=Instance.new("WorldModel"); world.Parent=viewport
local camera=Instance.new("Camera"); camera.FieldOfView=35; camera.Parent=viewport; viewport.CurrentCamera=camera
local info=text("Info",UDim2.new(1,-168,0,128),UDim2.fromOffset(156,60),15); info.TextXAlignment=Enum.TextXAlignment.Left
local function button(name,label,width,x)
 local b=Instance.new("TextButton"); b.Name=name; b.Text=label; b.Size=UDim2.fromOffset(width,52); b.Position=UDim2.new(.5,x,1,-62); b.BackgroundColor3=Color3.fromRGB(35,117,121); b.TextColor3=Color3.new(1,1,1); b.Font=Enum.Font.GothamMedium; b.TextSize=16; b.BorderSizePixel=0; b.Parent=panel
 local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,10); corner.Parent=b; return b
end
local open=button("OpenInventory","보관함에서 보기",144,-148)
local close=button("Close","닫기",128,12)
local focusId
local function hide() shade.Visible=false; p:SetAttribute("SeaLegendRewardOpen",false) end
close.Activated:Connect(hide)
shade.Activated:Connect(hide)
open.Activated:Connect(function()
 hide()
 p.PlayerGui:WaitForChild("SeaInventoryHUD"):WaitForChild("OpenSeaInventory_Stage9"):Fire(focusId)
end)
RS.SeaCapture_Stage2.CaptureResult.OnClientEvent:Connect(function(r)
 if not r.legend then return end
 focusId=r.id
 world:ClearAllChildren()
 local m=RS.CreaturePreviews_Stage8[r.speciesId]:Clone(); m:ScaleTo(r.scale); m.Parent=world; m:PivotTo(CFrame.identity)
 local cf,size=m:GetBoundingBox(); camera.CFrame=CFrame.lookAt(cf.Position+Vector3.new(1,.7,1).Unit*size.Magnitude*1.3,cf.Position)
 title.Text=r.kind=="New" and "새 전설 발견 · 해신룡!" or "새 해신룡 개체를 만났어요!"
 info.Text=string.format("크기 %.2f배 · %s\n현재 전투력 %d\n코인 +1 · 흔적 0/20\n기존 장착은 유지됩니다",r.scale,r.trait,r.power)
 shade.Visible=true; p:SetAttribute("SeaLegendRewardOpen",true)
end)
p.CharacterRemoving:Connect(hide)
local hints=Instance.new("Folder"); hints.Name="PersonalHints_Stage9"; hints.Parent=root
local motes={}
for i=1,4 do
 local a=i*math.pi/2
 local v=Instance.new("Part"); v.Name="TraceScale_"..i; v.Shape=Enum.PartType.Ball; v.Size=Vector3.new(.7,1.2,.4); v.CFrame=CFrame.new(320+math.cos(a)*4,12.2,18+math.sin(a)*2); v.Anchored=true; v.CanCollide=false; v.CanTouch=false; v.CanQuery=false; v.Material=Enum.Material.Neon; v.Color=Color3.fromRGB(94,234,247); v.Parent=hints; motes[i]=v
end
local beacon=Instance.new("Part"); beacon.Name="ReadyBeacon"; beacon.Size=Vector3.new(.5,12,.5); beacon.Position=Vector3.new(320,18,18); beacon.Anchored=true; beacon.CanCollide=false; beacon.CanTouch=false; beacon.CanQuery=false; beacon.Material=Enum.Material.Neon; beacon.Color=Color3.fromRGB(96,245,255); beacon.Parent=hints
local function updateHints()
 local n=p:GetAttribute("SeaDragonTraces") or 0
 local unlocked=(p:GetAttribute("HighestSpeedTraining") or 0)>=150
 for i,m in ipairs(motes) do m.Transparency=unlocked and n>=i*5 and .15 or 1 end
 beacon.Transparency=unlocked and n>=20 and not p:GetAttribute("SeaDragonRitual") and .4 or 1
end
p:GetAttributeChangedSignal("SeaDragonRitual"):Connect(updateHints)
p:GetAttributeChangedSignal("SeaDragonTraces"):Connect(updateHints)
p:GetAttributeChangedSignal("HighestSpeedTraining"):Connect(updateHints)
updateHints()
