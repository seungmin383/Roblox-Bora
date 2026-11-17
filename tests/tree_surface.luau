local r=require('@lune/roblox')
local mesher=require('../src/TreeMesher')(r.Vector3)
local a=r.Vector3.new(0,1,0)
local direction=r.Vector3.new(1,.35,.27).Unit
local b=a+direction*8
local function rod(count)
	local segments={}
	for i=1,count do
		table.insert(segments,{A=a:Lerp(b,(i-1)/count),B=a:Lerp(b,i/count),R0=.35,R1=.35,PathId='one-limb'})
	end
	return mesher.build({Config={Thickness=1},Segments=segments})
end
local single,many=rod(1),rod(16)
-- Adding centerline samples must not add a collar at every sample joint.
assert(#single.Vertices==#many.Vertices and #single.Faces==#many.Faces,'Subdividing one limb changed its surface topology')
local sum,worst=0,0
for i,v in single.Vertices do
	assert(((v+single.Center)-(many.Vertices[i]+many.Center)).Magnitude<.0001,'Artificial bulge at a centerline sample')
	local p=v+single.Center
	local t=math.clamp((p-a):Dot(direction),0,8)
	local error=math.abs((p-a-direction*t).Magnitude-.35)
	sum+=error*error; worst=math.max(worst,error)
end
local rms=math.sqrt(sum/#single.Vertices)
print('Rod surface radius error: rms',rms,'max',worst)
assert(rms<.025 and worst<.06,'Surface sampling introduced visible radius waves')
print('PASS: limb subdivision invariance and smooth oblique tube radius.')
