local Players=game:GetService("Players")
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local getter=game.ServerScriptService:WaitForChild("TrainingServer_Stage6"):WaitForChild("GetTrainingStats")
local check=Instance.new("BindableFunction"); check.Name="CheckAccess"; check.Parent=script
local function allowed(p,zone)
 local z=Catalog.Zones[zone]; if not z then return false end
 local stats=getter:Invoke(p)
 return stats and stats.highest>=z.Required
end
local function notice(p,zone)
 p:SetAttribute("SeaAccessNotice",Catalog.Zones[zone].Name.." · 속도 최고 기록 "..Catalog.Zones[zone].Required.." 필요")
 p:SetAttribute("SeaAccessNoticeUntil",workspace:GetServerTimeNow()+2)
end
check.OnInvoke=function(p,zone)
 local ok=allowed(p,zone); if not ok and p.Parent then notice(p,zone) end; return ok
end
local timers={}
Players.PlayerRemoving:Connect(function(p) timers[p]=nil end)
local elapsed=0
game:GetService("RunService").Heartbeat:Connect(function(dt)
 elapsed+=dt; if elapsed<.15 then return end; elapsed=0
 for _,p in ipairs(Players:GetPlayers()) do
  local c=p.Character; local h=c and c:FindFirstChildOfClass("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
  if h and h.Health>0 and r then
   local pos=r.Position; local sea=pos.X>=154 and pos.X<=440 and math.abs(pos.Z)<=220
   local zone=sea and (pos.X>=286 and "far" or pos.X>=210 and "coral" or "beach") or ""
   p:SetAttribute("CurrentSeaZone",zone)
   if sea then
    local denied=pos.X>=210 and not allowed(p,"coral") and "coral" or pos.X>=286 and not allowed(p,"far") and "far" or nil
    if denied and p.Character==c and os.clock()>=(timers[p] or 0) then
     timers[p]=os.clock()+1.2
     r.AssemblyLinearVelocity=Vector3.zero; r.AssemblyAngularVelocity=Vector3.zero
     c:PivotTo(CFrame.new(denied=="coral" and 200 or 276,14.3,48))
     notice(p,denied)
    end
   end
  end
 end
end)