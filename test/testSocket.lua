-- To test LuaTerminal module

-- package.path = package.path..";./src/?.lua"	-- For Zerobrane
package.path = package.path..";./../src/?.lua"

require("iuplua")
lt = require("LuaTerminal")
-- Create terminal
local sENV = {io={}}
setmetatable(sENV,{__index = _ENV})
setmetatable(sENV.io,{__index = _ENV.io})

newsterm = lt.newSocketTerm(sENV,true,"testSocklog.txt")
print(newsterm,newsterm.timer)
print(newsterm.timer.run)

local tENV = {io = {}}
setmetatable(tENV,{__index = _ENV})
setmetatable(tENV.io,{__index = _ENV.io})

-- Create terminal
newterm = lt.newTerm(tENV,true,"testlog.txt")
--print("newterm: ", newterm)
ltbox = iup.vbox{newterm}

dlg = iup.dialog{ltbox; title="LuaTerminal", size="QUARTERxQUARTER"}
dlg:show()


if (iup.MainLoopLevel()==0) then
  iup.MainLoop()
end
newsterm.timer:destroy()