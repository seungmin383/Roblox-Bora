-- Owns one moving cab and its passengers. Destroy/error always releases riders.
return function(api,Motion)
	local A={};A.__index=A;local S=1/.28;local C=api.CFrame
	function A.new(model,characters)
		local stops={};for floor=1,model:GetAttribute('Floors') do stops[floor]=model.Stops['Floor_'..floor].Value/S end
		local self=setmetatable({Model=model,Characters=characters,State=Motion.new(stops),Riders={},CabParts={},LandingDoors={},Connections={}},A)
		local base=model.ShaftOrigin.CFrame;self.Base=base
		for _,p in model.Cab:GetDescendants() do if p:IsA('BasePart') then
			table.insert(self.CabParts,{Part=p,Frame=base:ToObjectSpace(p.CFrame),Side=p:GetAttribute('DoorSide')})
		end end
		for floor=1,#stops do
			local landing=model.Landings['Floor_'..floor]
			for _,name in {'DoorLeft','DoorRight'} do local p=landing[name];table.insert(self.LandingDoors,{Part=p,Frame=base:ToObjectSpace(p.CFrame),Side=p:GetAttribute('DoorSide'),Floor=floor}) end
		end
		self:pose();return self
	end
	function A:inside(character)
		if not character then return nil end
		local root=character:FindFirstChild('HumanoidRootPart');local h=character:FindFirstChildOfClass('Humanoid')
		if not root or not h or h.Health<=0 or h.SeatPart then return nil end
		local frame=self.Base*C.new(0,self.State.Y*S,0);local p=frame:PointToObjectSpace(root.CFrame.Position)/S
		if math.abs(p.X)>.98 or math.abs(p.Z)>1.04 or p.Y<.25 or p.Y>2.4 then return nil end
		return root,frame:ToObjectSpace(root.CFrame)
	end
	function A:capture()
		for _,character in self.Characters() do
			local root,relative=self:inside(character)
			if root and not root.Anchored then
				self.Riders[root]={Relative=relative,Anchored=root.Anchored,Character=character};root.Anchored=true
				if api.Vector3 then root.AssemblyLinearVelocity=api.Vector3.zero;root.AssemblyAngularVelocity=api.Vector3.zero end
			end
		end
	end
	function A:doorBlocked()
		local frame=self.Base*C.new(0,self.State.Y*S,0)
		for _,character in self.Characters() do
			local root=character:FindFirstChild('HumanoidRootPart');local h=character:FindFirstChildOfClass('Humanoid')
			if root and h and h.Health>0 then
				local p=frame:PointToObjectSpace(root.CFrame.Position)/S
				if math.abs(p.X)<.8 and p.Z> -1.75 and p.Z< -.75 and p.Y>.25 and p.Y<2.4 then return true end
			end
		end
		return false
	end
	function A:release()
		for root,rider in self.Riders do
			root.Anchored=rider.Anchored
			if api.Vector3 then root.AssemblyLinearVelocity=api.Vector3.zero;root.AssemblyAngularVelocity=api.Vector3.zero end
		end
		table.clear(self.Riders)
	end
	function A:pose()
		local s=self.State;local frame=self.Base*C.new(0,s.Y*S,0)
		for _,piece in self.CabParts do
			local offset=if piece.Side then C.new(piece.Side*.66*S*s.Door,0,0) else C.new()
			piece.Part.CFrame=frame*offset*piece.Frame
		end
		for _,piece in self.LandingDoors do
			local open=if piece.Floor==s.Floor and s.Phase~='Moving' then s.Door else 0
			piece.Part.CFrame=self.Base*C.new(piece.Side*.67*S*open,0,0)*piece.Frame
		end
		for root,rider in self.Riders do
			local h=rider.Character:FindFirstChildOfClass('Humanoid')
			if root.Parent and h and h.Health>0 then root.CFrame=frame*rider.Relative
			else root.Anchored=rider.Anchored;self.Riders[root]=nil end
		end
		self.Model:SetAttribute('CurrentFloor',s.Floor);self.Model:SetAttribute('ElevatorPhase',s.Phase)
		local panel=self.Model.Cab:FindFirstChild('ControlPanel')
		if panel and panel:FindFirstChild('Display') then panel.Display.FloorText.Text=tostring(s.Floor)..'층'..(if s.Phase=='Moving' then ' 이동 중' else '') end
	end
	function A:step(dt)
		if self.State.Phase=='Closing' and self:doorBlocked() then self.State.Door=1;self:pose();return end
		local previous=self.State.Phase;Motion.step(self.State,dt)
		if previous~='Moving' and self.State.Phase=='Moving' then self:capture() end
		self:pose()
		if previous=='Moving' and self.State.Phase~='Moving' then self:release() end
	end
	function A:destroy()
		self:release();for _,connection in self.Connections do connection:Disconnect() end;table.clear(self.Connections)
	end
	return A
end
