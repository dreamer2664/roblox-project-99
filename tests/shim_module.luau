local H = require("./spec_helper")
local V = H.V
return { new = function(x, y, z) return V.new(x, y, z) end }
