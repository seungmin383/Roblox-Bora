local Players=game:GetService("Players")
local root=workspace:WaitForChild("CentralHub_Stage5")
local origin=root:WaitForChild("HubOrigin")
local elapsed=0
game:GetService("RunService").Heartbeat:Connect(function(dt)
 elapsed+=dt; if elapsed<.25 then return end; elapsed=0
 for _,p in ipairs(Players:GetPlayers()) do
  local c=p.Character; local hrp=c and c:FindFirstChild("HumanoidRootPart")
  local inside=hrp and Vector2.new(hrp.Position.X-origin.Position.X,hrp.Position.Z-origin.Position.Z).Magnitude<=56 and hrp.Position.Y>-2
  p:SetAttribute("InCentralSafeZone",inside==true)
  if c then
   local existing=c:FindFirstChild("CentralSafeZone_Stage5")
   if inside and not existing then local f=Instance.new("ForceField"); f.Name="CentralSafeZone_Stage5"; f.Visible=false; f.Parent=c
   elseif not inside and existing then existing:Destroy() end
  end
 end
end)