-- To test LuaTerminal module

require("iuplua")
require("iuplua_scintilla")
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