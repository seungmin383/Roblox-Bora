local Players=game:GetService("Players")
local player=Players.LocalPlayer
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local Growth=require(game.ReplicatedStorage:WaitForChild("TrainingRules_Stage6"))
local folder=player:WaitForChild("SeaCreatures_Stage3")
local equip=game.ReplicatedStorage.SeaCapture_Stage2:WaitForChild("EquipIndividual")
local gui=Instance.new("ScreenGui"); gui.Name="SeaInventoryHUD"; gui.ResetOnSpawn=false; gui.DisplayOrder=60; gui.Parent=player:WaitForChild("PlayerGui")
local function button(name,parent,text,size,pos)
 local b=Instance.new("TextButton"); b.Name=name; b.Size=size; b.Position=pos; b.Text=text; b.Font=Enum.Font.GothamMedium; b.TextSize=16; b.TextColor3=Color3.fromRGB(241,249,240); b.BackgroundColor3=Color3.fromRGB(30,91,94); b.BorderSizePixel=0; b.Parent=parent
 local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,10); corner.Parent=b; return b
end
local toggle=button("MyCreatures",gui,"내 생물 · 0마리",UDim2.fromOffset(180,42),UDim2.fromOffset(16,66))
local shade=button("ModalShade",gui,"",UDim2.fromScale(1,1),UDim2.fromScale(0,0)); shade.BackgroundColor3=Color3.new(0,0,0); shade.BackgroundTransparency=.4; shade.Visible=false; shade.AutoButtonColor=false
local panel=Instance.new("Frame"); panel.Name="InventoryPanel"; panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5); panel.Size=UDim2.fromScale(.96,.86); panel.BackgroundColor3=Color3.fromRGB(17,42,54); panel.BorderSizePixel=0; panel.Parent=shade
local max=Instance.new("UISizeConstraint"); max.MaxSize=Vector2.new(660,560); max.Parent=panel
local header=Instance.new("TextLabel"); header.Name="Summary"; header.BackgroundTransparency=1; header.Position=UDim2.fromOffset(12,4); header.Size=UDim2.new(1,-160,0,60); header.TextColor3=Color3.fromRGB(243,248,240); header.Font=Enum.Font.GothamMedium; header.TextSize=16; header.TextWrapped=true; header.TextXAlignment=Enum.TextXAlignment.Left; header.Parent=panel
header.TextScaled=true
local textCap=Instance.new("UITextSizeConstraint"); textCap.MinTextSize=12; textCap.MaxTextSize=16; textCap.Parent=header
local close=button("Close",panel,"보관함 닫기",UDim2.fromOffset(128,52),UDim2.new(1,-136,0,6))
local scroll=Instance.new("ScrollingFrame"); scroll.Name="Individuals"; scroll.Position=UDim2.fromOffset(10,70); scroll.Size=UDim2.new(1,-20,1,-80); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=6; scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.fromScale(0,0); scroll.Parent=panel
local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,8); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Parent=scroll
local function open(value,focusId)
 shade.Visible=value; player:SetAttribute("SeaInventoryOpen",value)
 if value and focusId then task.spawn(function()
  task.wait(.08)
  for _,row in ipairs(scroll:GetChildren()) do if row:IsA("Frame") and row:GetAttribute("IndividualId")==focusId then
   local y=row.AbsolutePosition.Y-scroll.AbsolutePosition.Y+scroll.CanvasPosition.Y
   scroll.CanvasPosition=Vector2.new(0,math.clamp(y,0,math.max(0,scroll.AbsoluteCanvasSize.Y-scroll.AbsoluteSize.Y)))
   break
  end end
 end) end
end
local openRequest=Instance.new("BindableEvent"); openRequest.Name="OpenSeaInventory_Stage9"; openRequest.Parent=gui
openRequest.Event:Connect(function(id) open(true,id) end)
toggle.Activated:Connect(function() open(not shade.Visible) end)
close.Activated:Connect(function() open(false) end)
shade.Activated:Connect(function() open(false) end)
local function refresh()
 local entries=folder:GetChildren()
 table.sort(entries,function(a,b) return (a:GetAttribute("CaptureIndex") or 0)<(b:GetAttribute("CaptureIndex") or 0) end)
 toggle.Text="내 생물 · "..#entries.."마리"
 header.Text=string.format("발견 %d종 · 보유 %d마리",player:GetAttribute("SeaSpeciesCount") or 0,#entries)
 for _,v in ipairs(scroll:GetChildren()) do if v:IsA("Frame") or v:IsA("TextLabel") then v:Destroy() end end
 if #entries==0 then
  local empty=Instance.new("TextLabel"); empty.Name="Empty"; empty.Size=UDim2.new(1,-8,0,70); empty.BackgroundTransparency=1; empty.Text="빛나는 물결에서 첫 생물을 찾아보세요"; empty.TextColor3=Color3.fromRGB(220,235,227); empty.TextSize=15; empty.TextWrapped=true; empty.Parent=scroll
 end
 for i,entry in ipairs(entries) do
  local row=Instance.new("Frame"); row.Name="Individual_"..i; row.Size=UDim2.new(1,-8,0,120); row:SetAttribute("IndividualId",entry.Name); row.LayoutOrder=i; row.BackgroundColor3=Color3.fromRGB(29,62,72); row.BorderSizePixel=0; row.Parent=scroll
  local info=Instance.new("TextLabel"); info.Name="Info"; info.Position=UDim2.fromOffset(12,8); info.Size=UDim2.new(1,-24,0,48); info.BackgroundTransparency=1; info.TextXAlignment=Enum.TextXAlignment.Left; info.TextYAlignment=Enum.TextYAlignment.Top; info.TextWrapped=true; info.Font=Enum.Font.GothamMedium; info.TextSize=15; info.TextColor3=Color3.fromRGB(245,246,230)
  info.Text=string.format("%s #%d · %.2f배 · %s\n원래 %d → 현재 전투력 %d",Catalog.Get(entry:GetAttribute("SpeciesId")).Name,i,entry:GetAttribute("SizeScale"),entry:GetAttribute("Trait"),entry:GetAttribute("BasePower"),Growth.Power(entry:GetAttribute("SizeScale"),player:GetAttribute("StrengthTraining") or 0,entry:GetAttribute("SpeciesId"))); info.Parent=row
  local selected=player:GetAttribute("SeaEquippedId")==entry.Name
  local choose=button("Equip",row,selected and "장착 중" or "장착",UDim2.fromOffset(144,52),UDim2.new(1,-156,1,-60))
  choose:SetAttribute("IndividualId",entry.Name)
  choose.Activated:Connect(function() equip:FireServer(entry.Name) end)
 end
end
folder.ChildAdded:Connect(refresh); folder.ChildRemoved:Connect(refresh)
player:GetAttributeChangedSignal("SeaEquippedId"):Connect(refresh)
player:GetAttributeChangedSignal("SeaSpeciesCount"):Connect(refresh)
player:GetAttributeChangedSignal("StrengthTraining"):Connect(refresh)
refresh()

player:GetAttributeChangedSignal("TrainingUpgradeOpen"):Connect(function() toggle.Visible=not player:GetAttribute("TrainingUpgradeOpen") end)
