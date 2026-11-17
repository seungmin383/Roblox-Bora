local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
local chunk=compiler.load(fs.readFile('src/DockPointer.luau'))
setfenv(chunk,setmetatable({Enum=r.Enum},{__index=getfenv()}))
local D=chunk()
local function event()
	local listeners={}
	return {
		Connect=function(_,fn)
			local connection={Connected=true,Fn=fn,Disconnect=function(self) self.Connected=false end}
			table.insert(listeners,connection);return connection
		end,
		Fire=function(_,...) for _,l in table.clone(listeners) do if l.Connected then l.Fn(...) end end end,
	}
end
local state=r.Enum.UserInputState
local track={InputEnded=event(),AbsoluteSize=r.Vector2.new(100,15),AbsolutePosition=r.Vector2.new(20,25)}
local changed=event()
local input={UserInputState=state.Begin,GetPropertyChangedSignal=function(_,name) assert(name=='UserInputState');return changed end}
local results={}
local function watch() input.UserInputState=state.Begin;return D.watch(track,input,function(commit) table.insert(results,commit) end) end
local handle=watch()
track.InputEnded:Fire({});assert(#results==0 and not handle.Poll())
input.UserInputState=state.End;changed:Fire();track.InputEnded:Fire(input)
assert(#results==1 and results[1]==true)
handle=watch();input.UserInputState=state.Cancel;assert(handle.Poll());assert(#results==2 and results[2]==false)
handle=watch();handle.Disconnect();track.InputEnded:Fire(input);changed:Fire();assert(#results==2)
watch();track.InputEnded:Fire(input);assert(#results==3 and results[3]==true)
local widget={GetRelativeMousePosition=function() return r.Vector2.new(45,0) end}
assert(D.ratio(widget,track)==.25);track.AbsoluteSize=r.Vector2.zero;assert(D.ratio(widget,track)==nil)
print('PASS: dock release without viewport, outside release, cancel, one commit and listener cleanup.')
