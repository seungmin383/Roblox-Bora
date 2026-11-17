-- Deterministic stop/door/travel controller; units are metres and seconds.
local M={}
function M.new(stops)
	assert(#stops>=2);return {Stops=stops,Floor=1,Y=stops[1],Phase='Idle',Door=1,Queue={},Speed=0,Clock=0}
end
function M.request(s,floor)
	if type(floor)~='number' or floor%1~=0 or not s.Stops[floor] then return false end
	if floor==s.Floor and s.Phase=='Idle' then s.Clock=0;return true end
	if floor==s.Target or table.find(s.Queue,floor) then return true end
	if #s.Queue>=#s.Stops then return false end
	table.insert(s.Queue,floor);return true
end
function M.step(s,dt)
	dt=math.clamp(dt,0,.1)
	if s.Phase=='Idle' then
		s.Clock+=dt
		if #s.Queue>0 and s.Clock>=1 then s.Target=table.remove(s.Queue,1);s.Phase='Closing';s.Clock=0 end
	elseif s.Phase=='Closing' then
		s.Door=math.max(0,s.Door-dt/.65)
		if s.Door==0 then s.Phase='Moving';s.Speed=0 end
	elseif s.Phase=='Moving' then
		local target=s.Stops[s.Target];local distance=math.abs(target-s.Y)
		s.Speed=math.min(1.8,s.Speed+2*dt,math.sqrt(4*distance))
		local travel=math.min(distance,s.Speed*dt)
		s.Y+=math.sign(target-s.Y)*travel
		if distance<=.002 or travel>=distance then s.Y=target;s.Floor=s.Target;s.Target=nil;s.Speed=0;s.Phase='Opening' end
	elseif s.Phase=='Opening' then
		s.Door=math.min(1,s.Door+dt/.65)
		if s.Door==1 then s.Phase='Idle';s.Clock=0 end
	end
	return s
end
return M
