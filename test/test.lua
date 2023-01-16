package.cpath = package.cpath .. ";../zig-out/lib/lib?.so"
local luz = require('luz')

local fd = luz.fs.create("test.txt")

p(luz)
p(fd)
p(getmetatable(fd))