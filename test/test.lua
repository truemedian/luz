package.cpath = package.cpath .. ";../zig-out/lib/lib?.so"
local luz = require('luz')

local fd = luz.fs.create("test.txt", "r");
print(fd:write("Hello, world!"))
fd:seekTo(0);
print(fd:read());
