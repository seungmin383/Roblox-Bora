local fs, serde, r = require("@lune/fs"), require("@lune/serde"), require("@lune/roblox")
local compiler = require("@lune/luau")
local rules = require("../src/GrowthMath")
local manifest = serde.decode("json", fs.readFile("assets/tree/local/manifest.json"))
local catalog = {}
for _, name in { "Wood" } do
	local item = manifest.parts[name]
	catalog[name] = { Mesh = "rbxasset://BoraTreeKitV3/" .. item.mesh,
		Texture = if item.texture then "rbxasset://BoraTreeKitV3/" .. item.texture else nil,
		Bounds = r.Vector3.new(table.unpack(item.bounds)) }
end
catalog.Leaf = { Texture = "rbxasset://BoraTreeKitV3/GinkgoCluster.png", Bounds = r.Vector3.new(1,1,0) }
catalog.WoodHeight, catalog.CrownAnchors = manifest.woodHeight, {}
for _, anchor in manifest.crownAnchors do table.insert(catalog.CrownAnchors,r.Vector3.new(table.unpack(anchor))) end
local factory = require("../src/GrowthTreeFactory")(r, rules, catalog)
local function expect(value, message) assert(value, message) end
local function near(a, b) return (a - b).Magnitude < .001 end
for _, file in { "src/GrowthMath.luau", "src/GrowthTreeFactory.luau", "src/TreeAssetCatalog.luau", "src/TreePlugin.server.luau", "tools/build_tree_v2.luau" } do
	expect(type(compiler.compile(fs.readFile(file))) == "string", "Compilation failed: " .. file)
end
local base = r.CFrame.new(13, 7, -24) * r.CFrame.Angles(0, .7, 0)
local tree = factory.create({ Growth = 0, Seed = 42, ObjectId = "stable-tree-id" }, base)
expect(tree:GetAttribute("Growth") == 0, "Placement must start at minimum growth")
expect(tree.PrimaryPart == tree.Root, "The base must be the model pivot")
local wood, leaves = {}, {}
for _, item in tree:GetDescendants() do
	if item:IsA("Part") and (item:FindFirstChild("Geometry") or item.Parent.Name == "Leaves") then
		wood[item.Name] = item
		if item.Parent.Name == "Leaves" then leaves[item.Name] = item end
	end
end
expect(#tree.Geometry.Leaves:GetChildren() == 84, "Wrong foliage budget")
expect(manifest.parts.Wood.connectedComponents == 1 and manifest.parts.Wood.manifold, "Wood is not a closed connected surface")
local identities = #tree:GetDescendants()
local smallestHeight = tree.Geometry.Trunk.Size.Y
local initial = tree.Geometry.Leaves.Leaves1.CFrame
local lastHeight, lastDiameter = 0, 0
for step = 0, 100 do
	factory.setGrowth(tree, step / 100)
	expect(near(tree.Root.CFrame.Position, base.Position), "Growth moved the ground anchor")
	expect(tree.Geometry.Trunk.Size.Y >= lastHeight and tree.Collision.Size.X >= lastDiameter, "Growth is not monotonic")
	lastHeight, lastDiameter = tree.Geometry.Trunk.Size.Y, tree.Collision.Size.X
	expect(near((base:Inverse()*tree.Geometry.Trunk.CFrame).Position-r.Vector3.new(0,tree.Geometry.Trunk.Size.Y/2,0),r.Vector3.zero), "Wood lifted from the ground")
	for _, part in wood do
		for _, component in { part.CFrame:GetComponents() } do expect(component == component and math.abs(component) < math.huge, "Nonfinite geometry") end
		if part:FindFirstChild("Geometry") then expect(part.Geometry.Scale.X > 0 and part.Geometry.Scale.Y > 0, "Invalid mesh scale") end
	end
end
expect(lastHeight > smallestHeight * 4, "Adult tree is too close to minimum size")
expect(#tree:GetDescendants() == identities, "Growth recreated the hierarchy")
expect(tree:GetAttribute("ObjectId") == "stable-tree-id", "Growth changed identity")
for _, part in wood do expect(part.Parent ~= nil, "Growth replaced a mesh part") end
for _, card in leaves do
	expect(card.Transparency == 1 and not card.CanCollide and not card:FindFirstChild("Geometry"), "Leaves must use transparent sprite cards")
	for _, face in { "Front", "Back" } do
		expect(card[face].Foliage.Image == catalog.Leaf.Texture and card[face].Foliage.BackgroundTransparency == 1, "Sprite lost image alpha background")
	end
end
factory.setGrowth(tree, 0)
expect(near(tree.Geometry.Leaves.Leaves1.CFrame.Position, initial.Position), "Growth does not reverse deterministically")
local restored = r.deserializeModel(r.serializeModel({ tree }, true))[1]
expect(restored:GetAttribute("ObjectId") == "stable-tree-id", "Save lost identity")
expect(restored.PrimaryPart == restored.Root, "Save lost the ground pivot")
factory.setGrowth(restored, .5)
expect(near(restored.Root.CFrame.Position, base.Position), "Loaded growth moved the base")
local relocated = r.CFrame.new(-14, 1, 12)
restored.Root.CFrame = relocated
factory.setGrowth(restored, .6)
expect(near(restored.Geometry.Trunk.CFrame.Position, relocated.Position + r.Vector3.new(0, restored.Geometry.Trunk.Size.Y / 2, 0)), "Growth ignored a moved tree")
expect(lastDiameter >= 2.19, "Mature trunk became thin again")
local topFacing = 0
for _, card in tree.Geometry.Leaves:GetChildren() do
	if math.abs(card.CFrame.LookVector.Y) > .75 then topFacing += 1 end
end
expect(topFacing >= 20, "Crown has no overhead leaf coverage")
local damaged = restored:Clone()
damaged:SetAttribute("SchemaVersion",2)
expect(not pcall(function() factory.setGrowth(damaged,.5) end), "v2 tree was silently changed")
expect(not pcall(function() factory.setGrowth(restored, 0/0) end), "Accepted NaN growth")
-- Single-project integration is checked in memory by project_update.py.
local pluginModel = r.deserializeModel(fs.readFile("dist/BoraTreeKit.rbxmx"))[1]
expect(pluginModel.TreePlugin.Source:find(':CreateButton%(') ~= nil, "Placement button missing")
print("PASS: compile, minimum placement, continuous growth, fixed geometry identity, reversibility, saving, and sprite cards.")
