local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local Tween=game:GetService("TweenService")
local root=workspace:WaitForChild("CentralHub_Stage5"):WaitForChild("Stage4_Exhibition")
local origin=root:WaitForChild("ArenaOrigin")
local function location(x,y,z) return origin.CFrame:PointToWorldSpace(Vector3.new(x,y,z)) end
local event=game.ReplicatedStorage:WaitForChild("SeaBattle_Stage4"):WaitForChild("BattleEvent")
local rules=require(script:WaitForChild("BattleRules"))
local owned=game.ServerScriptService:WaitForChild("SeaCaptureServer_Stage2"):WaitForChild("GetOwnedIndividual_Stage4")
local templates=game.ReplicatedStorage:WaitForChild("CreaturePreviews_Stage8")
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
local prompt=root.ChallengeAnchor.Challenge
local rng=Random.new()
local champion={id="npc_guard",speciesId="coral_crab",scale=math.sqrt(.8),trait="수호",power=80,ownerId=0,ownerName="NPC 연습 수호자",defenses=0,originalPower=80,strengthAtSnapshot=0}
local current=nil
local cooldowns={}
local function visual(record,name,parent,cf)
 local template=assert(templates:FindFirstChild(record.speciesId),"Missing species preview")
 local m=template:Clone(); m.Name=name
 for _,p in ipairs(m:GetDescendants()) do if p:IsA("BasePart") then p.Anchored=true; p.CanCollide=false; p.CanTouch=false; p.CanQuery=false end end
 local scale=record.scale*Catalog.VisualScale(record.speciesId,"BattleScale")
 m:SetAttribute("SpeciesId",record.speciesId); m:SetAttribute("IndividualSize",record.scale); m:SetAttribute("VisualScale",scale)
 m:ScaleTo(scale); m:PivotTo(cf); m.Parent=parent; return m
end
local function preparedDisplay(record)
 return visual(record,"ChampionDisplay",nil,origin.CFrame*CFrame.new(10,3,9)*CFrame.Angles(0,math.pi,0))
end
local function display(record,model)
 local old=root:FindFirstChild("ChampionDisplay")
 model.Parent=root
 if old then old:Destroy() end
 root:SetAttribute("ChampionSpeciesId",record.speciesId); root:SetAttribute("ChampionName",Catalog.Get(record.speciesId).Name)
 root:SetAttribute("ChampionId",record.id); root:SetAttribute("ChampionOwnerId",record.ownerId)
 root:SetAttribute("ChampionOwner",record.ownerName); root:SetAttribute("ChampionScale",record.scale)
 root:SetAttribute("ChampionTrait",record.trait); root:SetAttribute("ChampionPower",record.power)
 root:SetAttribute("Defenses",record.defenses)
 root:SetAttribute("ChampionStrengthAtSnapshot",record.strengthAtSnapshot or 0)
 root:SetAttribute("ChampionOriginalPower",record.originalPower or record.power)
 root.Board.SurfaceGui.Label.Text=string.format("%s\n%s · %.2f배 · %s\n전시 당시 전투력 %d · 방어 %d회",record.ownerName,Catalog.Get(record.speciesId).Name,record.scale,record.trait,record.power,record.defenses)
end
local function cleanup(b)
 if b.done then return end
 b.done=true
 for _,r in ipairs(b.resources or {}) do
  r.tween:Cancel(); r.connection:Disconnect(); r.value:Destroy()
 end
 if b.models then b.models:Destroy() end
 if b.nextDisplay then b.nextDisplay:Destroy() end
 if current==b then current=nil; root:SetAttribute("Busy",false); root:SetAttribute("Phase","대기"); root:SetAttribute("ChallengerUserId",0); root:SetAttribute("BattleMode","") end
end
local function valid(b)
 local c=b.player.Character; local hum=c and c:FindFirstChildOfClass("Humanoid")
 if b.done or current~=b or not b.player.Parent or c~=b.character or not hum or hum.Health<=0 then error("Challenge canceled",0) end
end
local function validStart(player,c)
 local h=c and c:FindFirstChildOfClass("Humanoid"); local r=c and c:FindFirstChild("HumanoidRootPart")
 return player.Parent and player.Character==c and h and h.Health>0 and r and (r.Position-root.ChallengeAnchor.Position).Magnitude<=12
end
local function phase(b,text) valid(b); root:SetAttribute("Phase",text) end
local function move(b,m,cf,duration)
 valid(b)
 local value=Instance.new("CFrameValue"); value.Value=m:GetPivot()
 local con=value.Changed:Connect(function(v) if m.Parent then m:PivotTo(v) end end)
 local tw=Tween:Create(value,TweenInfo.new(duration,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Value=cf})
 local resource={value=value,connection=con,tween=tw}; table.insert(b.resources,resource)
 tw:Play(); tw.Completed:Wait(); con:Disconnect(); value:Destroy(); valid(b)
end
local function reject(player,text) if player.Parent then event:FireClient(player,{kind="Rejected",text=text}) end end
root:SetAttribute("Busy",false); root:SetAttribute("Phase","대기"); root:SetAttribute("ChallengerUserId",0); root:SetAttribute("BattleMode","")
display(champion,preparedDisplay(champion))
prompt.Triggered:Connect(function(player)
 if current then reject(player,"이미 전투 중입니다"); return end
 local c=player.Character
 if not validStart(player,c) then return end
 if workspace:GetServerTimeNow()<(cooldowns[player.UserId] or 0) then reject(player,"잠시 후 다시 도전하세요"); return end
 local reservation={player=player,character=c}
 current=reservation
 root:SetAttribute("Busy",true); root:SetAttribute("ChallengerUserId",player.UserId)
 task.delay(2,function() if current==reservation then cleanup(reservation) end end)
 local lookupOK,snapshot=pcall(function() return owned:Invoke(player) end)
 if current~=reservation then return end
 if not lookupOK or not snapshot then cleanup(reservation); reject(player,"보관함에서 생물을 먼저 장착하세요"); return end
 if not validStart(player,c) then cleanup(reservation); return end
 local replacement=champion.ownerId==player.UserId
 if replacement and snapshot.id==champion.id then cleanup(reservation); reject(player,"현재 대표와 다른 개체를 장착하세요"); return end
 snapshot.ownerId=player.UserId; snapshot.ownerName=player.DisplayName
 local b={player=player,character=c,attacker=table.clone(snapshot),defender=table.clone(champion),replacement=replacement,resources={}}
 current=b; cooldowns[player.UserId]=workspace:GetServerTimeNow()+12
 root:SetAttribute("BattleMode",replacement and "Replacement" or "Challenge")
 root:SetAttribute("BattleSerial",(root:GetAttribute("BattleSerial") or 0)+1)
 -- Install cleanup before resolving or creating either visual.
 task.delay(12,function() if current==b and not b.done then cleanup(b); reject(player,"대전이 중단됐습니다. 다시 도전할 수 있어요") end end)
 task.spawn(function()
  local ok,err=xpcall(function()
   local result=rules.Resolve(b.attacker,b.defender,rng:NextNumber(0,.30),rng:NextNumber(0,.30),rng:NextInteger(0,1)==1)
   b.models=Instance.new("Folder"); b.models.Name="ActiveBattleCopies"; b.models.Parent=root
   local a=visual(b.attacker,"ChallengerCopy",b.models,CFrame.lookAt(location(-8,1,0),location(8,1,0)))
   local d=visual(b.defender,"DefenderCopy",b.models,CFrame.lookAt(location(8,1,0),location(-8,1,0)))
   phase(b,"서로 마주 보기"); task.wait(1)
   phase(b,"다가가기"); move(b,a,CFrame.lookAt(location(-3,1,0),location(5,1,0)),.65); move(b,d,CFrame.lookAt(location(3,1,0),location(-3,1,0)),.65); task.wait(.3)
   phase(b,"도전자 공격 · 수호자 방어"); move(b,a,CFrame.lookAt(location(0,1.3,0),location(3,1,0)),.4); move(b,a,CFrame.lookAt(location(-3,1,0),location(3,1,0)),.4); task.wait(.6)
   phase(b,"수호자 반격"); move(b,d,CFrame.lookAt(location(0,1.3,0),location(-3,1,0)),.4); move(b,d,CFrame.lookAt(location(3,1,0),location(-3,1,0)),.4); task.wait(.6)
   phase(b,"결정타"); local winner=result.winner=="Challenger" and a or d; local loser=result.winner=="Challenger" and d or a
   move(b,winner,winner:GetPivot()+origin.CFrame:VectorToWorldSpace(Vector3.new(result.winner=="Challenger" and 2 or -2,.5,0)),.45)
   move(b,loser,loser:GetPivot()+origin.CFrame:VectorToWorldSpace(Vector3.new(result.winner=="Challenger" and 3 or -3,-.35,0)),.45); task.wait(1.7)
   valid(b)
   local nextChampion
   if result.winner=="Challenger" then nextChampion=table.clone(b.attacker); nextChampion.defenses=0
   else nextChampion=table.clone(b.defender); if not b.replacement then nextChampion.defenses+=1 end end
   -- Prepare the replacement before touching the old champion or its display.
   b.nextDisplay=preparedDisplay(nextChampion)
   valid(b)
   champion=nextChampion
   display(champion,b.nextDisplay); b.nextDisplay=nil
   result.replacement=b.replacement; result.attackerSpeciesId=b.attacker.speciesId; result.defenderSpeciesId=b.defender.speciesId
   result.kind="Result"; result.attackerId=b.attacker.id; result.defenderId=b.defender.id; result.owner=champion.ownerName
   root:SetAttribute("LastResult",Http:JSONEncode(result))
   if not b.replacement then root:SetAttribute("CompletedBattles",(root:GetAttribute("CompletedBattles") or 0)+1) end
   -- One-time journey facts are not wins, defenses, currency or repeatable rewards.
   player:SetAttribute("ArenaFirstBattleDone",true)
   if b.attacker.speciesId=="sea_dragon" then player:SetAttribute("ArenaDragonBattleDone",true) end
   event:FireClient(player,result)
  end,debug.traceback)
  cleanup(b)
  if not ok then
   reject(player,"전투가 취소됐습니다. 생물과 전시는 그대로 보관됩니다")
   if not string.find(tostring(err),"Challenge canceled",1,true) then warn(err) end
  end
 end)
end)
Players.PlayerRemoving:Connect(function(player) cooldowns[player.UserId]=nil; if current and current.player==player then cleanup(current) end end)
local function watch(player) player.CharacterRemoving:Connect(function() if current and current.player==player then cleanup(current) end end) end
Players.PlayerAdded:Connect(watch); for _,p in ipairs(Players:GetPlayers()) do watch(p) end
