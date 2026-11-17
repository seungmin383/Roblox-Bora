local C={}
C.Species={
 sea_dragon={Name="해신룡",BasePower=400,ToolScale=.30,BattleScale=.40,RevealScale=3},
 coral_crab={Name="산호게",BasePower=100},
 droplet_ray={Name="물방울가오리",BasePower=120},
 glass_jelly={Name="유리해파리",BasePower=150},
}
C.Zones={
 beach={Name="해변",Required=0,Table={{"coral_crab",1}}},
 coral={Name="산호 구역",Required=50,Table={{"droplet_ray",.8},{"coral_crab",.2}}},
 far={Name="먼바다",Required=150,Table={{"glass_jelly",.8},{"droplet_ray",.2}}},
}
function C.Get(id) return assert(C.Species[id or "coral_crab"],"Unknown species") end
function C.VisualScale(id,field) return C.Get(id)[field] or 1 end
function C.Roll(zone,u)
 local rows=assert(C.Zones[zone],"Unknown zone").Table
 local total=0
 for _,row in ipairs(rows) do total+=row[2]; if u<total then return row[1] end end
 return rows[#rows][1]
end
return C