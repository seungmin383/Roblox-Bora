-- A dock widget owns the mouse press; the viewport input service is separate.
local D={}
function D.watch(track,input,onEnd)
	local state=Enum.UserInputState
	local stateConnection,releaseConnection
	local watching=true
	local function disconnect()
		if not watching then return end
		watching=false
		if stateConnection then stateConnection:Disconnect() end
		if releaseConnection then releaseConnection:Disconnect() end
	end
	local function finish(commit)
		if not watching then return end
		disconnect();onEnd(commit)
	end
	local function poll()
		if not watching then return true end
		local value=input.UserInputState
		if value==state.End or value==state.Cancel then finish(value==state.End);return true end
		return false
	end
	stateConnection=input:GetPropertyChangedSignal('UserInputState'):Connect(poll)
	releaseConnection=track.InputEnded:Connect(function(released)
		if released==input then finish(input.UserInputState~=state.Cancel) end
	end)
	return {Disconnect=disconnect,Poll=poll}
end
function D.ratio(widget,track)
	local width=track.AbsoluteSize.X
	if width<=0 then return nil end
	return math.clamp((widget:GetRelativeMousePosition().X-track.AbsolutePosition.X)/width,0,1)
end
return D
