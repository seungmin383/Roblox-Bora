return function(api)
	local Instance,Vector3,CFrame,Vector2,UDim2,Enum=api.Instance,api.Vector3,api.CFrame,api.Vector2,api.UDim2,api.Enum
	local Guide={DefaultImage='rbxasset://BoraRoadKit/MapReference.png',Aspect=2036/3970,StudsPerMeter=1/.28}
	function Guide.isGuide(model)
		return model and model:IsA('Model') and model:GetAttribute('AssetKind')=='BoraMapGuide'
	end
	function Guide.update(model,width,rotation,opacity)
		assert(Guide.isGuide(model),'지도가 없습니다.')
		assert(width==width and width>=100 and width<=16000,'지도 폭은 100~16000 studs입니다.')
		assert(rotation==rotation and math.abs(rotation)<=180,'회전 범위를 확인하세요.')
		assert(opacity==opacity and opacity>=0 and opacity<=1,'지도 진하기 범위를 확인하세요.')
		local aspect=model:GetAttribute('Aspect') or Guide.Aspect
		local widthChanged=model:GetAttribute('Width')~=width
		local height=width*aspect
		local base=CFrame.new(model.Root.CFrame.Position)*CFrame.Angles(0,math.rad(rotation),0)
		local tiles=Instance.new('Folder'); tiles.Name='Tiles'
		local columns,rows=math.ceil(width/2000),math.ceil(height/2000)
		for row=0,rows-1 do for column=0,columns-1 do
			local u0,v0,du,dv=column/columns,row/rows,1/columns,1/rows
			local part=Instance.new('Part'); part.Name='MapTile'
			-- Texture top-face U/V axes are -X/-Z. Image right/down follow
			-- map -X/-Z, matching Studio's standard top view.
			part.Size=Vector3.new(width*du,.04,height*dv)
			part.CFrame=base*CFrame.new((.5-u0-du*.5)*width,0,(.5-v0-dv*.5)*height)
			part:SetAttribute('U0',u0); part:SetAttribute('V0',v0)
			part.Transparency,part.Anchored,part.CanCollide,part.CanTouch,part.CanQuery=1,true,false,false,false
			part.Parent=tiles
			-- SurfaceGui depth bias hides nearby roads at map-editing zoom.
			-- A physical surface texture keeps the road at its real height.
			local image=Instance.new('Texture'); image.Name='ReferenceImage'
			image.Face,image.Texture=Enum.NormalId.Top,model:GetAttribute('Image') or Guide.DefaultImage
			image.StudsPerTileU,image.StudsPerTileV=width,height
			image.OffsetStudsU,image.OffsetStudsV=u0*width,v0*height
			image.Transparency=if model:GetAttribute('Visible')~=false then 1-opacity else 1
			image.Parent=part
		end end
		local old=model:FindFirstChild('Tiles')
		if old then old.Name='PreviousTiles'; if api.Retire then api.Retire(old) else old:Destroy() end end
		model.Root.CFrame,tiles.Parent=base,model
		model:SetAttribute('Width',width); model:SetAttribute('Rotation',rotation); model:SetAttribute('Opacity',opacity)
		model:SetAttribute('DisplayVersion',6)
		if widthChanged then model:SetAttribute('Calibrated',false) end
	end
	function Guide.create()
		local model=Instance.new('Model'); model.Name='BoraMapReference'
		model:SetAttribute('AssetKind','BoraMapGuide'); model:SetAttribute('Aspect',Guide.Aspect)
		model:SetAttribute('Image',Guide.DefaultImage); model:SetAttribute('Visible',true)
		local root=Instance.new('Part'); root.Name,root.Size,root.CFrame='Root',Vector3.one*.1,CFrame.new(850,.03,0)
		root.Transparency,root.Anchored,root.CanCollide,root.CanTouch,root.CanQuery=1,true,false,false,false
		root.Parent=model; model.PrimaryPart=root
		Guide.update(model,1200,0,.9)
		return model
	end
	function Guide.visible(model,value)
		model:SetAttribute('Visible',value)
		for _,item in model.Tiles:GetDescendants() do
			if item:IsA('Texture') then item.Transparency=if value then 1-model:GetAttribute('Opacity') else 1 end
		end
	end
	function Guide.calibrate(model,a,b,meters)
		assert(type(meters)=='number' and meters==meters and meters>0 and meters<=10000,'실제 거리를 m 단위로 입력하세요.')
		local delta=Vector3.new(b.X-a.X,0,b.Z-a.Z)
		assert(delta.Magnitude>=1,'기준점 두 개를 더 멀리 찍으세요.')
		local factor=meters*Guide.StudsPerMeter/delta.Magnitude
		local oldPosition=model.Root.CFrame.Position
		local width=model:GetAttribute('Width')*factor
		assert(width>=100 and width<=16000,'축척 결과가 너무 크거나 작습니다. 거리와 기준점을 확인하세요.')
		Guide.update(model,width,model:GetAttribute('Rotation'),model:GetAttribute('Opacity'))
		local position=Vector3.new(a.X+(oldPosition.X-a.X)*factor,oldPosition.Y,a.Z+(oldPosition.Z-a.Z)*factor)
		local move=position-model.Root.CFrame.Position
		for _,part in model.Tiles:GetChildren() do part.CFrame+=move end
		model.Root.CFrame+=move
		model:SetAttribute('Calibrated',true); model:SetAttribute('CalibrationMeters',meters)
		return factor
	end
	return Guide
end
