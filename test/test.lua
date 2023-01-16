package.cpath = arg[1]
local luz = require('luz')

print("Works", arg[1]:match("[^/]+$"))