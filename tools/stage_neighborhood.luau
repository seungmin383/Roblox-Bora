local r,fs,compiler=require('@lune/roblox'),require('@lune/fs'),require('@lune/luau')
compiler.compile(fs.readFile('src/NeighborhoodFactory.luau'))
require('./build_neighborhood')()
