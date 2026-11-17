-- Versioned, saved recipe. Percent controls are converted to ratios by the UI.
local Parameters = {}
Parameters.Version = 1
Parameters.Defaults = { BranchCount = 9, Spread = 1, Thickness = 1, LeafDensity = 1, Seed = 42 }
Parameters.Limits = { BranchCount = {4,14}, Spread = {.65,1.4}, Thickness = {.65,1.5}, LeafDensity = {0,1.5}, Seed = {0,2147483646} }
function Parameters.normalize(input)
	local out = {}
	for name, default in Parameters.Defaults do
		local value = if input[name] == nil then default else input[name]
		assert(type(value) == "number" and value == value and math.abs(value) < math.huge, name .. " must be finite")
		local limits = Parameters.Limits[name]
		assert(value >= limits[1] and value <= limits[2], name .. " is out of range")
		if name == "BranchCount" or name == "Seed" then assert(value % 1 == 0, name .. " must be an integer") end
		out[name] = value
	end
	return out
end
function Parameters.fromModel(model)
	local version=model:GetAttribute("RecipeVersion")
	assert(version==nil or version==Parameters.Version,"Unsupported tree recipe version")
	local values = {}
	for name in Parameters.Defaults do values[name] = model:GetAttribute(name) end
	return Parameters.normalize(values)
end
return Parameters
