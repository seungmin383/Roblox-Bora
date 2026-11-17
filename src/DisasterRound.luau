local Round={}

function Round.survivors(roster,isAlive)
	local alive={}
	for player,character in roster do
		if isAlive(player,character) then table.insert(alive,player) end
	end
	return alive
end

function Round.run(config,world)
	world.phase('Intermission',config.Intermission)
	world.wait(config.Intermission)
	local roster=world.enroll()
	local entrants=0
	for _ in roster do entrants+=1 end
	if entrants==0 then return end

	world.phase('Warning',config.Warning,entrants,entrants)
	world.wait(config.Warning)
	local deadline=world.now()+config.Active
	world.phase('Active',config.Active,entrants,entrants)
	while world.now()+config.StrikeTime<=deadline do
		local alive=Round.survivors(roster,world.isAlive)
		world.update(#alive)
		if #alive==0 then break end
		world.strike(alive)
	end

	local winners=Round.survivors(roster,world.isAlive)
	world.finish(roster,winners)
	world.phase('Results',config.Results,entrants,#winners)
	world.wait(config.Results)
end

return Round
