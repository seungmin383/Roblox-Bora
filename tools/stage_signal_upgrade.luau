-- Read the single Place; export only model fragments for an XML-level update.
-- Never serialize the world through Lune (unknown Studio payloads must survive).
local r,fs,serde,process=require('@lune/roblox'),require('@lune/fs'),require('@lune/serde'),require('@lune/process')
local Path=require('../src/RoadPath')(r.Vector3)
local Traffic=require('../src/RoadTraffic')(r,Path,nil,require('../src/TrafficAssetLayout'))
local roads
if process.args[1] then
	roads=r.deserializeModel(fs.readFile(process.args[1]))[1]
else
	local xml=fs.readFile('Ro.rbxlx'):gsub('^<%?xml.-%?>%s*','')
	local place=r.deserializePlace(xml)
	roads=place:GetService('Workspace'):FindFirstChild('BoraRoads')
end
local root=r.Instance.new('Model');root.Name='SignalUpgrade'
local report={Signals=0,LeftHeads=0,Approaches={}}
local junctions=roads and roads:FindFirstChild('Junctions')
if junctions then for _,junction in junctions:GetChildren() do
	local signals=junction:FindFirstChild('Signals')
	if signals then
		local group=r.Instance.new('Folder');group.Name,group.Parent=junction.Name,root
		for _,original in signals:GetChildren() do
			local arm=original:GetAttribute('Arm') or tonumber(original.Name:match('^Signal_(%d+)$'))
			assert(arm,'Unknown signal arm: '..original.Name)
			local mask=Traffic.savedMask(junction,arm)
			assert(mask,'Saved approach has no lane directions: '..junction.Name..'/'..original.Name)
			local signal=original:Clone()
			Traffic.configureSignal(signal,arm,mask)
			for _,item in signal:GetChildren() do
				if not table.find({'Red','Amber','Green','Left','GreenHousing','LeftBacking'},item.Name) then item:Destroy() end
			end
			signal.Parent=group;report.Signals+=1
			if bit32.band(mask,2)~=0 then report.LeftHeads+=1 end
			table.insert(report.Approaches,{Junction=junction.Name,Signal=signal.Name,Arm=arm,Mask=mask})
		end
	end
end end
fs.writeFile('dist/SignalUpgrade.rbxmx',r.serializeModel({root},true))
fs.writeFile('dist/signal-upgrade-plan.json',serde.encode('json',report,true))
print('Staged signal-only upgrade: '..report.Signals..' signals / '..report.LeftHeads..' left arrows. Place unchanged.')
