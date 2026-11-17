-- Run a normal test with its output in the task directory, never in the project.
local fs,compiler,process=require('@lune/fs'),require('@lune/luau'),require('@lune/process')
local test=assert(process.args[1]);assert(test:match('^[a-z][a-z_0-9]*$') and test~='run_local_audit')
local temp=assert(process.env.BORA_BUILDINGS_WORK);local reports=temp..'/results/'..test
if not fs.isDir(reports) then fs.writeDir(reports) end
local scratch=table.clone(fs)
local function staged(path)
	local file=path:match('^dist/(Bora%a+Kit%.rbxmx)$')
	if file and fs.isFile(temp..'/'..file) then return temp..'/'..file end
	return path
end
function scratch.readFile(path) return fs.readFile(staged(path)) end
function scratch.writeFile(path,contents)
	local file=path:match('^dist/([%w_.-]+)$') or path:match('^assets/tree/local/([%w_.-]+)$')
	assert(file and not file:lower():match('%.rbxlx?$'),'Unexpected test output path: '..path)
	return fs.writeFile(reports..'/'..file,contents)
end
local chunk=compiler.load(fs.readFile('tests/'..test..'.luau'),{debugName=test})
setfenv(chunk,setmetatable({require=function(file) return if file=='@lune/fs' then scratch else require(file) end},{__index=getfenv()}))
chunk()
