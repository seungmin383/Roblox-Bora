-- Session-only authoritative coins and personal training equipment. No persistence or client setters.
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local Rules=require(game.ReplicatedStorage:WaitForChild("TrainingEquipmentRules_Stage11"))
local states={}
local E={}
local function publish(p,s)
 p:SetAttribute("SeaCoins",s.coins)
 p:SetAttribute("TrainingEquipmentLevel",s.level)
 p:SetAttribute("TrainingEquipmentVersion",s.version)
 p:SetAttribute("TrainingEquipmentMultiplier",Rules.Multipliers[s.level])
 -- One complete replicated view for the purchase panel.
 p:SetAttribute("TrainingEquipmentState",Http:JSONEncode({coins=s.coins,level=s.level,version=s.version}))
end
local function init(p)
 if not states[p] then states[p]={coins=0,level=0,version=0}; publish(p,states[p]) end
 return states[p]
end
function E.Snapshot(p)
 local s=states[p] or init(p)
 return {coins=s.coins,level=s.level,version=s.version}
end
function E.Multiplier(p) return Rules.Multipliers[(states[p] or init(p)).level] end
function E.Publish(p) local s=states[p] or init(p); publish(p,s) end
-- Callers hold the player's existing growth-action lock. Both mutations below never yield.
function E.AwardCapture(p)
 local s=states[p] or init(p); s.coins+=1; publish(p,s)
end
function E.Purchase(p,expectedVersion)
 local s=states[p]
 if not s then return false,"장비 정보를 준비 중이에요" end
 if type(expectedVersion)~="number" or expectedVersion~=expectedVersion or expectedVersion%1~=0 or expectedVersion<0 then return false,"잘못된 구매 요청이에요" end
 if expectedVersion~=s.version then return false,"장비 상태가 바뀌었어요 · 현재 정보를 확인하세요" end
 if s.level>=Rules.MaxLevel then return false,"최대 등급이에요 · 코인은 차감하지 않아요" end
 local cost=Rules.Costs[s.level]; local nextLevel=s.level+1
 if not cost or not Rules.Multipliers[nextLevel] or s.coins<0 or s.coins%1~=0 then return false,"장비 정보를 확인할 수 없어요" end
 if s.coins<cost then return false,string.format("코인 %d개가 더 필요해요",cost-s.coins) end
 -- All validation precedes this non-yielding commit: no charge-only state and no stale replay.
 s.coins-=cost; s.level=nextLevel; s.version+=1; publish(p,s)
 return true,string.format("장비 %d등급 강화 완료",s.level)
end
Players.PlayerAdded:Connect(init)
Players.PlayerRemoving:Connect(function(p) states[p]=nil end)
for _,p in ipairs(Players:GetPlayers()) do init(p) end
return E