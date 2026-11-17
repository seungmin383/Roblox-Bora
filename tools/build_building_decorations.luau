-- Native, shared mesh templates. Source files use metres; local frames use studs.
return function()
	local r,fs,serde=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde')
	local catalog=serde.decode('json',fs.readFile('assets/buildings/local/manifest.json'))
	local root=r.Instance.new('Model');root.Name='Decorations'
	local lamp=r.Instance.new('Model');lamp.Name,lamp.Parent='WallSconce',root
	lamp:SetAttribute('SourceTask',catalog.SourceTask);lamp:SetAttribute('Triangles',catalog.TotalTriangles)
	for i,spec in catalog.Parts do
		local p=r.Instance.new('Part');p.Name='Sconce_'..i;p.Size=r.Vector3.new(table.unpack(spec.Bounds))/.28
		p.CFrame=r.CFrame.new();p.Color=r.Color3.fromRGB(table.unpack(spec.Color));p.Material=r.Enum.Material[spec.Material]
		p.Transparency=spec.Transparency;p.Anchored=true;p.CanCollide,p.CanQuery,p.CanTouch=false,false,false;p.Parent=lamp
		local mesh=r.Instance.new('SpecialMesh');mesh.MeshType=r.Enum.MeshType.FileMesh
		mesh.MeshId='rbxasset://BoraBuildingKit/'..spec.File;mesh.Scale=r.Vector3.new(1,1,1)/.28;mesh.Parent=p
	end
	fs.writeFile('dist/BuildingDecorations.rbxmx',r.serializeModel({root},true))
	print('Packaged cleaned Tripo sconce: '..catalog.TotalTriangles..' triangles in 3 material parts.')
end
