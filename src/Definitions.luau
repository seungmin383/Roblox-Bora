-- 설정과 모습의 기준을 한곳에 모아 여러 맵에서 같은 에셋을 재사용합니다.
local Definitions = {}

Definitions.SchemaVersion = 1
Definitions.Seasons = { "Spring", "Summer", "Autumn", "Winter" }
Definitions.BranchCounts = { Sparse = 3, Normal = 5, Dense = 7 }
Definitions.Species = {
	Ginkgo = {
		Label = "은행나무",
		Bark = { 110, 91, 68 },
		Spring = { 156, 190, 80 }, Summer = { 101, 151, 63 },
		Autumn = { 239, 192, 48 }, Winter = { 156, 143, 121 },
	},
	Maple = {
		Label = "단풍나무",
		Bark = { 105, 82, 66 },
		Spring = { 137, 176, 84 }, Summer = { 72, 131, 68 },
		Autumn = { 194, 70, 43 }, Winter = { 153, 138, 122 },
	},
	Pine = {
		Label = "소나무",
		Bark = { 105, 73, 52 },
		Spring = { 58, 113, 79 }, Summer = { 43, 94, 66 },
		Autumn = { 51, 100, 66 }, Winter = { 46, 85, 66 },
	},
}

return Definitions
