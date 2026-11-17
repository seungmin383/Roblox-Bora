return function(V)
	local F={Speed=170,Lifetime=5,Interval=1.15}
	local function finite(v) return v==v and math.abs(v)<1e6 end
	function F.aim(origin,target)
		if typeof(target)~='Vector3' or not finite(target.X) or not finite(target.Y) or not finite(target.Z) then return nil end
		local delta=target-origin
		if delta.Magnitude<.15 or delta.Magnitude>6000 then return nil end
		return delta.Unit
	end
	function F.advance(flight,dt,cast)
		local time=math.min(math.max(0,dt),F.Lifetime-flight.Age)
		if time<=0 then return nil,true end
		local delta=flight.Direction*(F.Speed*time)
		local hit=cast(flight.Position,delta)
		flight.Age+=time
		if hit then flight.Position=hit.Position;return hit,true end
		flight.Position+=delta
		return nil,flight.Age>=F.Lifetime
	end
	return F
end
