-- To test LuaTerminal module

-- package.path = package.path..";./src/?.lua"	-- For Zerobrane
package.path = package.path..";./../src/?.lua"

require("iuplua")
lt = require("LuaTerminal")

-- Create terminal
newterm = lt.newTerm(_ENV,true,"testlog.txt")
--print("newterm: ", newterm)
ltbox = iup.vbox{newterm}

dlg = iup.dialog{ltbox; title="LuaTerminal", size="QUARTERxQUARTER"}
dlg:show()

if (iup.MainLoopLevel()==0) then
  iup.MainLoop()
end