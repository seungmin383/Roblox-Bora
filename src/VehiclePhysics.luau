-- Stable ground-following arcade motion. Wheels are visual, not suspension.
return function(api,D)
	local V,C=api.Vector3,api.CFrame
	local P={}
	local codes={'FL','FR','RL','RR'}
	local function forward(yaw) return V.new(-math.sin(yaw),0,-math.cos(yaw)) end
	local function pose(position,yaw,up)
		local f=forward(yaw);f=(f-up*f:Dot(up)).Unit
		local right=f:Cross(up).Unit
		return C.fromMatrix(position,right,right:Cross(f).Unit,-f)
	end
	function P.new(car,world,rayParams)
		local root=car.Chassis
		local self={Car=car,Root=root,Speed=0,Spin=0,Steer=0}
		local wheels={}
		for _,code in codes do
			local joint=car.Mechanics['Wheel'..code]
			wheels[code]={Joint=joint,Closed=joint:GetAttribute('ClosedC0')}
		end
		function self:reset()
			self.Speed=0;self.Steer=0
			local f=root.CFrame.LookVector
			self.Yaw=math.atan2(-f.X,-f.Z)
			self.Ground=nil
		end
		self:reset()
		local function ground(position,yaw)
			local heading=C.new(position)*C.Angles(0,yaw,0)
			local points={};local centerHit=false;local normal=V.zero
			local function probe(offset,center)
				local p=heading:PointToWorldSpace(offset)
				local hit=world:Raycast(p+V.yAxis*D.ProbeUp,-V.yAxis*(D.ProbeUp+D.ProbeDown),rayParams)
				if not hit or hit.Normal.Y<.88 then return end
				local h=hit.Position
				table.insert(points,{X=h.X-position.X,Z=h.Z-position.Z,Y=h.Y})
				normal+=hit.Normal
				if center then centerHit=true end
			end
			probe(V.zero,true)
			for _,code in codes do
				local p=wheels[code].Closed.Position
				probe(V.new(p.X,0,p.Z),false)
			end
			if #points==0 or (not centerHit and #points<3) then return nil end
			local n=#points;local sx,sz,sy,sxx,szz,sxz,sxy,szy=0,0,0,0,0,0,0,0
			for _,p in points do
				sx+=p.X;sz+=p.Z;sy+=p.Y;sxx+=p.X*p.X;szz+=p.Z*p.Z;sxz+=p.X*p.Z;sxy+=p.X*p.Y;szy+=p.Z*p.Y
			end
			local xx,zz,xz=sxx-sx*sx/n,szz-sz*sz/n,sxz-sx*sz/n
			local xy,zy=sxy-sx*sy/n,szy-sz*sy/n
			local det=xx*zz-xz*xz
			local a,b
			if math.abs(det)>.00001 then a,b=(xy*zz-zy*xz)/det,(zy*xx-xy*xz)/det
			else normal=normal.Unit;a,b=-normal.X/normal.Y,-normal.Z/normal.Y end
			if a*a+b*b>D.MaxSlope*D.MaxSlope then return nil end
			local y=(sy-a*sx-b*sz)/n
			-- Keep the rigid wheel plane above small unevenness without springs.
			for _,p in points do y=math.max(y,p.Y-a*p.X-b*p.Z) end
			return {Y=y,Up=V.new(-a,1,-b).Unit}
		end
		function self:step(dt,input)
			dt=math.clamp(dt,0,.05);if dt==0 then return end
			root.Anchored=true
			root.AssemblyLinearVelocity=V.zero;root.AssemblyAngularVelocity=V.zero
			local old=root.CFrame.Position
			local current=ground(old,self.Yaw)
			if not current then self.Speed=0;car:SetAttribute('SpeedKmh',0);return end
			local acceleration,target=D.control(self.Speed,input)
			local before=self.Speed
			self.Speed+=acceleration*dt
			if (input.Brake or input.Throttle==0) and before*self.Speed<0 then self.Speed=0 end
			self.Steer+=(target-self.Steer)*(1-math.exp(-dt*12))
			local rate=self.Speed/D.Wheelbase*math.tan(self.Steer)
			local limit=math.rad(100)/(1+math.abs(self.Speed/D.Scale)/35)
			rate=math.clamp(rate,-limit,limit)
			local turn=rate*dt
			local movement=forward(self.Yaw+turn*.5)*self.Speed*dt
			local targetPosition=old+movement
			local nextGround=ground(targetPosition,self.Yaw+turn)
			local rise=if nextGround then nextGround.Y-current.Y else math.huge
			if not nextGround or rise>D.MaxStep+movement.Magnitude*D.MaxSlope or -rise>D.MaxDrop+movement.Magnitude*D.MaxSlope then
				movement=V.zero;turn=0;self.Speed=0;nextGround=current
			elseif movement.Magnitude>.00001 then
				local start=V.new(old.X,current.Y+D.RideHeight/current.Up.Y,old.Z)
				local cast=pose(start,self.Yaw+turn*.5,current.Up)*C.new(0,.22*D.Scale,0)
				local endY=nextGround.Y+D.RideHeight/nextGround.Up.Y
				local delta=V.new(movement.X,endY-start.Y,movement.Z)
				local hit=world:Blockcast(cast,V.new(1.9,1.2,4.65)*D.Scale,delta+delta.Unit*(.06*D.Scale),rayParams)
				if hit then
					local fraction=math.clamp((hit.Distance-.06*D.Scale)/delta.Magnitude,0,1)
					movement*=fraction;turn*=fraction;self.Speed=0
					nextGround=ground(old+movement,self.Yaw+turn) or current
				end
			end
			self.Yaw+=turn;self.Ground=nextGround
			local position=V.new(old.X+movement.X,nextGround.Y+D.RideHeight/nextGround.Up.Y,old.Z+movement.Z)
			root.CFrame=pose(position,self.Yaw,nextGround.Up)
			local distance=movement:Dot(forward(self.Yaw-turn*.5))
			self.Spin=(self.Spin-distance/D.Radius)%(math.pi*2)
			for _,code in codes do
				local w=wheels[code]
				local steer=if code:sub(1,1)=='F' then D.wheelAngle(self.Steer,w.Closed.Position.X) else 0
				w.Joint.C0=w.Closed*C.Angles(0,steer,0)*C.Angles(self.Spin,0,0)
			end
			car.Mechanics.Steering.C0=car.Mechanics.Steering:GetAttribute('ClosedC0')*C.fromAxisAngle(V.new(0,.5,.866025404),self.Steer*4)
			car:SetAttribute('SpeedKmh',math.floor(math.abs(self.Speed)/D.Scale*3.6+.5))
		end
		return self
	end
	return P
end
