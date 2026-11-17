-- Exercise the same serializer used by kit builds, without creating a Place.
local r = require('@lune/roblox')
local fs = require('@lune/fs')
local names = {utf8.char(0xB3C4,0xB85C), utf8.char(0xC740,0xD589,0xB098,0xBB34)}
for _,name in names do
	local model = r.Instance.new('Model'); model.Name=name
	for _=1,8 do
		local xml=r.serializeModel({model},true)
		model=r.deserializeModel(xml)[1]
		assert(model.Name==name,'Unicode instance name changed during XML round trip')
	end
end
-- Numeric references in the distributable plugin must decode back into the
-- exact source text, including UI labels, arrows and Korean string literals.
for _,entry in {
	{'BoraRoadKit','RoadPlugin','src/RoadEditorPlugin.server.luau'},
	{'BoraTreeKit','TreePlugin','src/ParametricTreePlugin.server.luau'},
} do
	local kit=r.deserializeModel(fs.readFile('dist/'..entry[1]..'.rbxmx'))[1]
	assert(kit:FindFirstChild(entry[2]).Source==fs.readFile(entry[3]),'Packaged Unicode source changed')
end
print('PASS: Korean names survive eight model XML round trips; packaged UI sources match exactly.')
