local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local definitions = require("../src/Definitions")
local trees = require("../src/TreeFactory")(roblox, definitions)
local roads = require("../src/RoadFactory")(roblox)
local Vector3, CFrame = roblox.Vector3, roblox.CFrame
-- Lune에는 Model:GetPivot 실행이 없어, PrimaryPart 없는 모델의 저장된 피벗을 읽습니다.
roblox.implementMethod("Model", "GetPivot", function(model) return model.WorldPivot end)
local checks = 0
local function check(condition, message)
	assert(condition, message)
	checks += 1
end
local function near(a, b)
	-- Roblox CFrame/Vector3 값은 단정밀도로 저장되므로 0.001 stud 오차를 허용합니다.
	return (a - b).Magnitude < 0.001
end
local function rejected(action, message)
	check(not pcall(action), message)
end
for _, path in { "src/Definitions.luau", "src/TreeFactory.luau", "src/RoadFactory.luau", "src/PluginMain.server.luau", "tools/build.luau" } do
	check(type(luau.compile(fs.readFile(path))) == "string", "Luau compilation failed: " .. path)
end

-- 시드, 모델 저장, 재생성을 거쳐도 위치와 모양이 유지되는지 확인합니다.
local transform = CFrame.new(17, 3, -29) * CFrame.Angles(0, 0.8, 0)
for _, species in { "Ginkgo", "Maple", "Pine" } do
	local tree = trees.create({ Species = species, ObjectId = species .. "-test", Seed = 7 }, transform)
	local count = 0
	for _, item in tree:GetDescendants() do
		if item:IsA("BasePart") then
			count += 1
			check(item.Anchored, "Tree geometry must not fall")
			check(item.Size.X > 0 and item.Size.Y > 0 and item.Size.Z > 0, "Invalid tree geometry")
			for _, value in { item.CFrame:GetComponents() } do
				check(value == value and math.abs(value) < math.huge, "Invalid tree transform")
			end
		end
	end
	check(count <= 16, "Tree exceeded the prototype geometry budget")
	local second = trees.create({ Species = species, Seed = 7 }, transform)
	for _, item in tree:GetDescendants() do
		if item:IsA("BasePart") then
			local sibling = second:FindFirstChild(item.Name, true)
			check(sibling and near(item.CFrame.Position, sibling.CFrame.Position),
				"Seed does not reproduce geometry: " .. species .. "/" .. item.Name .. " (match=" .. tostring(sibling) .. ")")
		end
	end
	trees.applySeason(tree, "Winter")
	for _, leaf in tree.Foliage:GetChildren() do
		check(leaf.Transparency == (if species == "Pine" then 0 else 1), "Wrong winter foliage")
		check(not leaf.CanCollide and not leaf.CanQuery, "Foliage blocks walking or editor raycasts")
	end
	trees.applySeason(tree, "Autumn")
	for _, leaf in tree.Foliage:GetChildren() do check(leaf.Transparency == 0, "Foliage did not return after winter") end
	local saved = roblox.deserializeModel(roblox.serializeModel({ tree }, true))[1]
	check(saved:GetAttribute("ObjectId") == species .. "-test", "Object ID lost during save")
	check(saved:GetAttribute("Season") == "Autumn", "Season lost during save")
	check(near(saved:GetPivot().Position, transform.Position), "Ground pivot lost during save")
	local parent = roblox.Instance.new("Folder")
	saved.Parent = parent
	local rebuilt = trees.rebuild(saved, { Height = 20 })
	check(rebuilt.Parent == parent and #parent:GetChildren() == 1, "Rebuild duplicated or lost tree")
	check(rebuilt:GetAttribute("ObjectId") == species .. "-test", "Rebuild changed stable identity")
	check(near(rebuilt:GetPivot().Position, transform.Position), "Rebuild moved the tree")
end
rejected(function() trees.create({ Species = "Unknown" }) end, "Invalid species accepted")
rejected(function() trees.create({ Height = -1 }) end, "Invalid tree size accepted")
rejected(function() trees.create({ Seed = 2.5 }) end, "Fractional seed accepted")
rejected(function() trees.create({ Height = 0/0 }) end, "NaN height accepted")

-- 경사 방향과 관계없이 표면 양끝이 입력한 끝점에 맞는지 확인합니다.
for _, points in {
	{ Vector3.new(0, 0, 0), Vector3.new(80, 12, 0) },
	{ Vector3.new(2, 8, 3), Vector3.new(-45, -2, 26) },
	{ Vector3.new(0, 0, 0), Vector3.new(0, 0, -64) },
} do
	local a, b = points[1], points[2]
	local road = roads.create({ Start = a, End = b, ObjectId = "road-test" })
	local asphalt = road.Asphalt
	local half = asphalt.Size.Z / 2
	local tip1 = (asphalt.CFrame * CFrame.new(0, asphalt.Size.Y / 2, half)).Position
	local tip2 = (asphalt.CFrame * CFrame.new(0, asphalt.Size.Y / 2, -half)).Position
	check((near(tip1, a) and near(tip2, b)) or (near(tip1, b) and near(tip2, a)), "Road surface misses endpoints")
	check(asphalt.Anchored and asphalt.CanCollide, "Road is not walkable")
	local saved = roblox.deserializeModel(roblox.serializeModel({ road }, true))[1]
	check(near(saved:GetAttribute("StartPosition"), a), "Road start lost on save")
	check(near(saved:GetAttribute("EndPosition"), b), "Road end lost on save")
end
local noSidewalk = roads.create({ Start = Vector3.zero, End = Vector3.new(20, 0, 0), SidewalkWidth = 0 })
check(not noSidewalk:FindFirstChild("SidewalkLeft"), "Zero-width sidewalk must not be generated")
rejected(function() roads.create({ Start = Vector3.zero, End = Vector3.zero }) end, "Zero-length road accepted")
rejected(function() roads.create({ Start = Vector3.zero, End = Vector3.new(20, 10, 0) }) end, "Unsafe slope accepted")
rejected(function() roads.create({ Start = Vector3.zero, End = Vector3.new(20, 0, 0), Width = -1 }) end, "Negative width accepted")

-- Single-project integration is checked in memory by project_update.py.
print(string.format("PASS: %d checks (Luau compile, trees, seasons, persistence, road geometry).", checks))
