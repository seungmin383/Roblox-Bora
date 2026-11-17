-- Engine adapter. The global welded surface is split only at the API face limit.
-- Shared positions and normals remain identical across chunk boundaries.
return function(AssetService, Content, Vector3, Vector2, Color3, Enum, barkTexture)
	return function(data)
		local parts={}
		local ok,err=pcall(function()
			for start=1,#data.Faces,18000 do
				local last=math.min(start+17999,#data.Faces)
				local used={}; local indices={}
				local minimum,maximum=Vector3.one*math.huge,Vector3.one*-math.huge
				for fi=start,last do for _,v in data.Faces[fi] do
					if not used[v] then used[v]=true; table.insert(indices,v); minimum=minimum:Min(data.Vertices[v]); maximum=maximum:Max(data.Vertices[v]) end
				end end
				table.sort(indices)
				local center=(minimum+maximum)*.5
				local editable=AssetService:CreateEditableMesh()
				assert(editable,"Could not allocate editable wood mesh")
				local part
				local built,buildError=pcall(function()
					local ids,normals,uvs={},{},{}
					for _,v in indices do
						ids[v]=editable:AddVertex(data.Vertices[v]-center)
						normals[v]=editable:AddNormal(data.Normals[v])
						uvs[v]=editable:AddUV(Vector2.new(data.UVs[v][1],1-data.UVs[v][2]))
					end
					for fi=start,last do
						local f=data.Faces[fi]
						local face=editable:AddTriangle(ids[f[1]],ids[f[2]],ids[f[3]])
						editable:SetFaceNormals(face,{normals[f[1]],normals[f[2]],normals[f[3]]})
						editable:SetFaceUVs(face,{uvs[f[1]],uvs[f[2]],uvs[f[3]]})
					end
					local result,content=AssetService:CreateDataModelContentAsync(Content.fromObject(editable))
					assert(result==Enum.CreateContentResult.Success,"Wood bake failed: "..tostring(result))
					part=AssetService:CreateMeshPartAsync(content,{CollisionFidelity=Enum.CollisionFidelity.Box})
					part.TextureID=barkTexture
					part.Color=Color3.new(1,1,1)
					part.DoubleSided=false
				end)
				editable:Destroy()
				if not built then if part then part:Destroy() end; error(buildError) end
				part.Name="Wood"..(#parts+1)
				part:SetAttribute("BaseSize",maximum-minimum)
				part:SetAttribute("BaseCenter",data.Center+center)
				part:SetAttribute("Triangles",last-start+1)
				table.insert(parts,part)
			end
		end)
		if not ok then for _,part in parts do part:Destroy() end; error(err) end
		return parts
	end
end
