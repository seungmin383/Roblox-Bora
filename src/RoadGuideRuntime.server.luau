-- The map is a drafting reference. Playable roads are ordinary saved Parts.
local guide=workspace:FindFirstChild('BoraMapReference')
if guide and guide:GetAttribute('AssetKind')=='BoraMapGuide' then
	for _,item in guide:GetDescendants() do
		if item:IsA('SurfaceGui') then item.Enabled=false end
		if item:IsA('Texture') then item.Transparency=1 end
	end
end
