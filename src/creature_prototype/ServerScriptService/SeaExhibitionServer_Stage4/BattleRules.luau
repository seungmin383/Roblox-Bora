local R={}
local beats={["돌파"]="수호",["수호"]="기습",["기습"]="돌파"}
function R.Advantage(a,b) return beats[a]==b and .15 or 0 end
function R.Resolve(a,b,ma,mb,tie)
 assert(a.power>0 and b.power>0)
 assert(ma>=0 and ma<=.30 and mb>=0 and mb<=.30)
 local aa,ab=R.Advantage(a.trait,b.trait),R.Advantage(b.trait,a.trait)
 local fa,fb=a.power*(1+aa+ma),b.power*(1+ab+mb)
 return {aBase=a.power,bBase=b.power,aAdvantage=aa,bAdvantage=ab,aMomentum=ma,bMomentum=mb,aFinal=fa,bFinal=fb,winner=fa>fb and "Challenger" or (fb>fa and "Defender" or (tie and "Challenger" or "Defender")),tie=fa==fb}
end
return R