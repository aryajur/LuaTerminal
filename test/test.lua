-- To test LuaTerminal module

require("iuplua")
require("iuplua_scintilla")
lt = require("LuaTerminal")
lt.USESCINTILLA = true
-- Create terminal
newterm,print = lt.newTerm(_ENV,true,"testlog.txt")
--print("newterm: ", newterm)
btn = iup.button{title="Print stuff"}
ltbox = iup.vbox{newterm,btn}

function btn:action()
	print("Hello this is the 1st line")
	print("Hello this is the second line")
end

dlg = iup.dialog{ltbox; title="LuaTerminal"}
dlg.size = nil
dlg:show()
dlg.minsize = dlg.rastersize
--iup.Show(iup.LayoutDialog(dlg))

if (iup.MainLoopLevel()==0) then
  iup.MainLoop()
end