-- Persisted, bounded recipes. Measurements are metres; frames are Roblox studs.
local P={Version=1}
P.Kinds={'Shop','Cafe','Pharmacy','Market','Residential','Apartment','House'}
P.KindLabels={'상가','카페','약국','마트','빌라','아파트','주택'}
P.Numbers={
	{'Floors','층수',3,1,24,1}, {'FloorHeight','상층 높이 · m',3.05,2.6,4.2,.05},
	{'GroundHeight','1층 높이 · m',3.45,2.8,5,.05}, {'Width','가로 · m',12,6,32,.1},
	{'Depth','깊이 · m',10,6,24,.1}, {'WindowWidth','창문 폭 · m',1.65,.8,2.4,.05},
	{'Apron','앞마당 깊이 · m',3,0,12,.1},
}
P.Defaults={Kind='Shop',Title='보라 상가',Wall='D2CAB5',Trim='E4DFCF',Accent='47675C',Sign=true,Balconies=false,Awning=true,Details=true,PlanJSON=''}
local function color(value,fallback)
	if value==nil then return fallback end
	assert(type(value)=='string','색상은 HEX 6자리입니다.')
	value=value:gsub('^#',''):upper()
	assert(#value==6 and value:match('^[0-9A-F]+$'),'색상은 HEX 6자리입니다.')
	return value
end
function P.normalize(config)
	config=config or {};local result={}
	result.Kind=config.Kind or P.Defaults.Kind
	assert(table.find(P.Kinds,result.Kind),'알 수 없는 건물 종류입니다.')
	for _,spec in P.Numbers do
		local n=config[spec[1]];if n==nil then n=spec[3] end
		assert(type(n)=='number' and n==n and math.abs(n)<math.huge,'올바른 숫자를 입력하세요: '..spec[2])
		n=math.clamp(n,spec[4],spec[5]);result[spec[1]]=math.floor(n/spec[6]+.5)*spec[6]
	end
	local title=if config.Title~=nil then config.Title else P.Defaults.Title
	assert(type(title)=='string' and utf8.len(title)~=nil,'간판 문자를 확인하세요.')
	assert(utf8.len(title)<=48,'간판은 48자 이내로 입력하세요.')
	result.Title=title:gsub('[%c]',' ')
	result.PlanJSON=config.PlanJSON or '';assert(type(result.PlanJSON)=='string' and #result.PlanJSON<=50000,'도면 저장 값을 확인하세요.')
	for _,key in {'Wall','Trim','Accent'} do result[key]=color(config[key],P.Defaults[key]) end
	for _,key in {'Sign','Balconies','Awning','Details'} do
		local value=config[key];if value==nil then value=P.Defaults[key] end
		assert(type(value)=='boolean','켜기/끄기 값을 확인하세요: '..key);result[key]=value
	end
	return result
end
function P.write(model,config)
	local p=P.normalize(config)
	for key,value in p do model:SetAttribute('BB_'..key,value) end
	model:SetAttribute('AssetKind','BoraBuilding');model:SetAttribute('BuildingSchema',P.Version)
	model:SetAttribute('Floors',p.Floors);model:SetAttribute('BuildingUse',p.Kind)
	return p
end
function P.read(model)
	local p={};for key in P.Defaults do p[key]=model:GetAttribute('BB_'..key) end
	for _,spec in P.Numbers do p[spec[1]]=model:GetAttribute('BB_'..spec[1]) end
	return P.normalize(p)
end
return P
