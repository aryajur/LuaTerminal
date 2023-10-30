-- To test LuaTerminal module
--require('mobdebug').coro()
require("wx")
lt = require("LuaTerminal")
lt.USESCINTILLA = false

-- First create the frame
local frame =  wx.wxFrame( wx.NULL,            -- no parent for toplevel windows
                        wx.wxID_ANY,          -- don't need a wxWindow ID
                        "LuaTerminal with Scintilla", -- caption on the frame
                        wx.wxDefaultPosition, -- let system place the frame
                        wx.wxSize(700,750),  -- set the size of the frame
                        wx.wxDEFAULT_FRAME_STYLE ) -- use default frame styles
-- Create terminal
newterm--[[,print,io.write,io.read]] = lt.newTerm(frame,_ENV,true,"testlog.txt")

local MainSizer = wx.wxBoxSizer(wx.wxVERTICAL)
MainSizer:Add(newterm.term,1,wx.wxEXPAND)
local hSizer = wx.wxBoxSizer(wx.wxHORIZONTAL)
MainSizer:Add(hSizer)
PrintButton = wx.wxButton(frame, wx.wxID_ANY, "Print Debug", wx.wxDefaultPosition, wx.wxDefaultSize, 0, wx.wxDefaultValidator)
hSizer:Add(PrintButton)
PrintButton:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED,function(event)
	print(newterm.term:GetLastPosition(),#newterm.Get(),#newterm.term:GetValue(),newterm.data.prompt,newterm.GetSelectionStart(),newterm.GetSelectionEnd(),newterm.GetCaretPos())
	print("--")
	print(newterm.Get())
	print("--")
	print(newterm.Get():sub(newterm.GetSelectionStart(),newterm.GetSelectionEnd()))
  end)
PrintButton2 = wx.wxButton(frame, wx.wxID_ANY, "History", wx.wxDefaultPosition, wx.wxDefaultSize, 0, wx.wxDefaultValidator)
hSizer:Add(PrintButton2)
PrintButton2:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED,function(event)
	for i = 1,#newterm.data.history do
		print(newterm.data.history[i])
	end
  end)
PrintButton3 = wx.wxButton(frame, wx.wxID_ANY, "Set Selection", wx.wxDefaultPosition, wx.wxDefaultSize, 0, wx.wxDefaultValidator)
hSizer:Add(PrintButton3)
PrintButton3:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED,function(event)
	newterm.SetSelection(2,4)
  end)
PrintButton4 = wx.wxButton(frame, wx.wxID_ANY, "io.write", wx.wxDefaultPosition, wx.wxDefaultSize, 0, wx.wxDefaultValidator)
hSizer:Add(PrintButton4)
PrintButton4:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED,function(event)
	io.write("This is io.write")
  end)
PrintButton5 = wx.wxButton(frame, wx.wxID_ANY, "io.read", wx.wxDefaultPosition, wx.wxDefaultSize, 0, wx.wxDefaultValidator)
hSizer:Add(PrintButton5)
PrintButton5:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED,function(event)
	print(io.read())
  end)
PrintButton5 = wx.wxButton(frame, wx.wxID_ANY, "Append Text", wx.wxDefaultPosition, wx.wxDefaultSize, 0, wx.wxDefaultValidator)
hSizer:Add(PrintButton5)
PrintButton5:Connect(wx.wxEVT_COMMAND_BUTTON_CLICKED,function(event)
	newterm.Append("\n")
	newterm.Append(">")
	newterm.data.prompt = newterm.GetLength()
  end)
frame:SetSizer(MainSizer)
MainSizer:SetSizeHints(frame)
frame:SetSize(wx.wxSize(700,700))
frame:Layout()


-- show the frame window
frame:Show(true)

wx.wxGetApp():MainLoop()