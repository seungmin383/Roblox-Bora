local R={}
local Catalog=require(game.ReplicatedStorage:WaitForChild("SpeciesCatalog_Stage8"))
function R.WalkSpeed(points) return math.min(40,16+math.max(0,points)*.1) end
function R.Power(size,strength,speciesId) return math.round(Catalog.Get(speciesId).BasePower*size*size*(1+math.max(0,strength)/1000)) end
function R.Requirement(rebirths) return math.ceil(100*1.5^rebirths) end
function R.Multiplier(rebirths) return 1+.5*rebirths end
return R