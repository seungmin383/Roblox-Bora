local p=game.Players.LocalPlayer
local root=workspace:WaitForChild("SeaRegion_Stage1"):WaitForChild("Stage8_Exploration")
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local walls={}
for _,id in ipairs({"coral","far"}) do
 local gate=root:WaitForChild(id.."_Gate")
 local wall=Instance.new("Part"); wall.Name="PersonalBoundary_"..id; wall.Size=Vector3.new(.7,10,10.5); wall.Position=Vector3.new(gate.Position.X,16.2,48); wall.Anchored=true; wall.Material=Enum.Material.ForceField; wall.Color=Color3.fromRGB(112,194,255); wall.CanTouch=false; wall.Parent=root
 walls[id]={part=wall,label=gate.ZoneSign.Label}
end
local function update()
 local high=p:GetAttribute("HighestSpeedTraining") or 0
 for id,item in pairs(walls) do
  local z=Catalog.Zones[id]; local ok=high>=z.Required
  item.part.CanCollide=not ok; item.part.Transparency=ok and 1 or .55
  item.label.Text=string.format("%s · 최고 속도 %d 필요\n내 최고 %.1f · %s",z.Name,z.Required,high,ok and "해금 완료" or "훈련이 더 필요해요")
 end
end
p:GetAttributeChangedSignal("HighestSpeedTraining"):Connect(update); update()