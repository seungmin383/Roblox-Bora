local Round=require('../src/DisasterRound')
local config={Intermission=4,Warning=2,Active=7,Results=3,StrikeTime=2}

local function play(roster,meteor)
	local now,strikes=0,0
	local phases={}
	local winnerList
	Round.run(config,{
		now=function() return now end,
		wait=function(n) now+=n end,
		enroll=function() return roster end,
		isAlive=function(player,character) return player.connected and player.character==character and character.alive end,
		phase=function(name,duration,entrants,alive)
			table.insert(phases,{Name=name,Duration=duration,Entrants=entrants,Alive=alive})
		end,
		update=function() end,
		strike=function(alive)
			strikes+=1
			meteor(strikes,alive)
			now+=config.StrikeTime
		end,
		finish=function(_,winners) winnerList=winners end,
	})
	return phases,winnerList,strikes
end

local function player()
	return {connected=true,character={alive=true}}
end
local survivor=player()
local reset=player()
local left=player()
local late=player()
local phases,winners,strikes=play({[survivor]=survivor.character,[reset]=reset.character,[left]=left.character},function(i,alive)
	for _,p in alive do assert(p~=late,'Late entrant joined an active round') end
	if i==1 then
		reset.character.alive=false
		reset.character={alive=true}
		left.connected=false
	else assert(#alive==1 and alive[1]==survivor) end
end)
assert(#phases==4 and phases[1].Name=='Intermission' and phases[2].Name=='Warning' and phases[3].Name=='Active')
assert(phases[4].Name=='Results' and phases[4].Entrants==3 and phases[4].Alive==1)
assert(strikes==3 and #winners==1 and winners[1]==survivor,'The round struck beyond its deadline or counted a respawn')

local doomed=player()
local _,none,early=play({[doomed]=doomed.character},function() doomed.character.alive=false end)
assert(#none==0 and early==1,'A depleted round must stop spawning hazards')
local idle,empty,noStrikes=play({},function() error('Empty round spawned a meteor') end)
assert(#idle==1 and empty==nil and noStrikes==0)
print('PASS: round phases, active deadline, eliminated and late players, results and empty lobbies.')
