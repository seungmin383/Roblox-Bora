local Timing={}
-- One protected movement runs at a time, including at skewed T/X junctions.
function Timing.program(approaches)
	local sorted=table.clone(approaches)
	table.sort(sorted,function(a,b) return a.Arm<b.Arm end)
	local phases,seen={},{}
	for _,approach in sorted do
		assert(type(approach.Arm)=='number' and approach.Arm%1==0 and approach.Arm>0 and not seen[approach.Arm],'Invalid signal arm')
		assert(type(approach.Mask)=='number' and approach.Mask%1==0 and approach.Mask>=1 and approach.Mask<=7,'Invalid signal mask')
		seen[approach.Arm]=true
		for _,movement in {{1,'Straight'},{2,'Left'}} do
			if bit32.band(approach.Mask,movement[1])~=0 then table.insert(phases,{Arm=approach.Arm,Movement=movement[2]}) end
		end
	end
	-- An all-right-turn layout still needs a vehicle interval between walks;
	-- it adds no right-turn lamp or protected right-turn movement.
	if #phases==0 and #approaches>0 then table.insert(phases,{Arm=0,Movement='Yield'}) end
	return phases
end
function Timing.duration(program,green,left,amber,clearance,walk,flash)
	local total=0
	for _,phase in program do total+=(if phase.Movement=='Left' then left else green)+amber+clearance end
	if walk>0 then total+=walk+flash+clearance end
	return total
end
function Timing.snapshot(time,program,green,left,amber,clearance,walk,flash)
	local total=Timing.duration(program,green,left,amber,clearance,walk,flash)
	local result={Movement='None',Stage='Clearance',Pedestrian='Red',WalkLit=false,PedestrianBlocked=false,CycleSeconds=total}
	if total<=0 then return result end
	local elapsed=time%total
	for _,phase in program do
		local duration=if phase.Movement=='Left' then left else green
		local span=duration+amber+clearance
		if elapsed<span then
			result.Arm=phase.Arm;result.Movement=phase.Movement
			result.Stage=if elapsed<duration then 'Green' elseif elapsed<duration+amber then 'Amber' else 'Clearance'
			return result
		end
		elapsed-=span
	end
	if walk>0 then
		result.PedestrianBlocked=true
		if elapsed<walk then result.Pedestrian='Walk';result.WalkLit=true
		elseif elapsed<walk+flash then result.Pedestrian='Flash';result.WalkLit=math.floor((elapsed-walk)*2)%2==0 end
	end
	return result
end
function Timing.lamps(snapshot,arm,mask)
	local active=snapshot.Arm==arm
	local straight=active and snapshot.Movement=='Straight' and bit32.band(mask,1)~=0
	local left=active and snapshot.Movement=='Left' and bit32.band(mask,2)~=0
	local green=straight and snapshot.Stage=='Green'
	local arrow=left and snapshot.Stage=='Green'
	local amber=(straight or left) and snapshot.Stage=='Amber'
	return {Red=not green and not amber,Amber=amber,Green=green,Left=arrow,
		StraightAllowed=green,LeftAllowed=arrow,
		RightTurnAllowed=bit32.band(mask,4)~=0 and not snapshot.PedestrianBlocked and snapshot.Stage~='Clearance',
		RightTurnMustYield=bit32.band(mask,4)~=0}
end
-- Compatibility helpers for previously generated two-phase models.
function Timing.state(time,phase,green,amber,clearance,walk,flash)
	local span=green+amber+clearance
	local pedestrian=if walk and walk>0 then walk+(flash or 0)+clearance else 0
	local cycle=time%(span*2+pedestrian)
	if cycle>=span*2 then return 'Red' end
	local active=if cycle<span then 1 else 2
	local elapsed=cycle%span
	if phase~=active or elapsed>=green+amber then return 'Red' end
	return if elapsed<green then 'Green' else 'Amber'
end
function Timing.pedestrian(time,green,amber,clearance,walk,flash)
	if walk<=0 then return 'Red',false end
	local start=(green+amber+clearance)*2
	local elapsed=time%(start+walk+flash+clearance)-start
	if elapsed<0 or elapsed>=walk+flash then return 'Red',false end
	if elapsed<walk then return 'Walk',true end
	return 'Flash',math.floor((elapsed-walk)*2)%2==0
end
return Timing
