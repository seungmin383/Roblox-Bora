-- 성장 값으로 치수를 계산해 슬라이더를 되돌리면 같은 모습으로 돌아오게 합니다.
local GrowthMath = {}
function GrowthMath.normalize(value)
	assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "Growth must be finite")
	return math.clamp(value, 0, 1)
end
function GrowthMath.smooth(value)
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end
function GrowthMath.dimensions(value)
	local growth = GrowthMath.normalize(value)
	return {
		Growth = growth,
		Height = 3 + 15 * growth ^ 0.72,
		Diameter = 0.22 + 1.98 * growth ^ 0.90,
		LeafSize = 0.38 + 3.92 * growth ^ 0.75,
	}
end
return GrowthMath
