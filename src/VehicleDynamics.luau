-- Pure controls/physics rules; all distances are Roblox studs.
local D={Scale=1/.28,Wheelbase=2.75/.28,Radius=.344/.28,RideHeight=.62/.28,
	ProbeUp=1/.28,ProbeDown=3/.28,MaxStep=.22/.28,MaxDrop=.35/.28,MaxSlope=math.tan(math.rad(26))}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
function D.input(data)
	if type(data)~='table' or not finite(data.Throttle) or not finite(data.Steer) or type(data.Brake)~='boolean' then return nil end
	if math.abs(data.Throttle)>1 or math.abs(data.Steer)>1 then return nil end
	return {Throttle=data.Throttle,Steer=data.Steer,Brake=data.Brake}
end
function D.control(speed,input)
	local mps=speed/D.Scale
	local angle=-input.Steer*math.rad(34)/(1+math.abs(mps)/16)
	local acceleration
	if input.Brake then acceleration=-math.clamp(mps*7,-16,16)
	elseif input.Throttle*mps<-.4 then acceleration=input.Throttle*12
	elseif input.Throttle~=0 then
		local limit=if input.Throttle>0 then 30 else 7
		acceleration=input.Throttle*7*math.clamp(1-math.abs(mps)/limit,0,1)
	else acceleration=-math.clamp(mps*1.2,-.8,.8) end
	return acceleration*D.Scale,angle
end
function D.canEnter(state,speed,healthy,distance)
	return state=='Empty' and math.abs(speed)<1 and healthy and distance<=12
end
function D.exitReady(speed) return math.abs(speed)<1.5 end
function D.wheelAngle(steer,x)
	if math.abs(steer)<.0001 then return 0 end
	local radius=D.Wheelbase/math.tan(steer)
	return math.atan(D.Wheelbase/(radius+x))
end
return D
