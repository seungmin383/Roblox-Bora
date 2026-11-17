local R={}
R.MaxLevel=3
R.Multipliers=table.freeze({[0]=1,[1]=1.25,[2]=1.5,[3]=1.75})
R.Costs=table.freeze({[0]=3,[1]=6,[2]=12})
function R.Format(n) return (string.format("%.3f",n):gsub("0+$",""):gsub("%.$","")) end
return table.freeze(R)