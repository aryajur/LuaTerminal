----------------------------------------------
-- Lua Terminal Module
-- Supports multiple terminals with independent command histories
-- @module LuaTerminal
-- @dependency iup
-- @dependency luasocket if terminal over socket is created
-- @date 9/3/2014

local wx = wx
local wxstc = wxstc

local type = type
local tonumber = tonumber
local tostring = tostring
local load = load
local require = require
local setmetatable = setmetatable
local pairs = pairs

local coroutine = coroutine
local io = io
local table = table
local package = package

-- For debugging
local print = print

-- Create the module table here
local M = {}
package.loaded[...] = M
_ENV = M		-- Lua 5.2+

-- Create the module table ends

_VERSION = "2.23.10.12"
MAXTEXT = 8192		-- maximum characters in text box
USESCINTILLA = false

local numOfTerms = 0	-- To maintain the number of terminals being managed
local numOfSockTerms = 0	-- To maintain the number of socket terminals being managed
local socket
local sockCR = "@#"
local offset = 0	-- Offset to the row and column indexes in case scintilla is used

-- Check some iup things to see if it is really loaded
if not wx or type(wx) ~= "table" then
	package.loaded[...] = nil
	return nil, "wxWidgets should be loaded in the global wx variable before loading the module."
end

if USESCINTILLA and (not wxstc or type(wxstc) ~= "function") then
	package.loaded[...] = nil
	return nil, "wxstc should be loaded if USESCINTILLA is set to true."
end

local incomplete = function (str)
	local f, err = load(str)
	return f == nil and (err:find(" expected .*near <eof>$") or err:find(" unexpected symbol near <eof>$") or err:find(" syntax error near <eof>$"))
end

local function action(term,event)
	local caret = term.GetCaretPos()
	local selst,selen = term.GetSelectionStart(),term.GetSelectionEnd()
	--print("action generated")
	--print("caret: ",caret)
	--print("selection: ", selection)
	--print("prompt: ",term.data.prompt)
	-- Ignore any editing done before the current prompt
	if caret < term.data.prompt then
		return
	end
	if selst then
		if selst < term.data.prompt then
			return
		end
	end
	event:Skip()
end

-- Function to trim the text in the beginning of the terminal to keep the terminal content within the MAXLENGTH
local function trimText(term)
	--print(#term.value,term.data.maxText,term.value)
	if term.GetLength() > term.data.maxText then
		--print(term.value:sub(-term.data.maxText,-1))
		-- Trim it justified with a line feed
		if term.Get():sub(-term.data.maxText-1,-term.data.maxText-1) == "\n" then
			term.Set(term.Get():sub(-term.data.maxText,-1))
		else
			term.Set(term.Get():sub(-term.data.maxText,-1):match(".-\n(.+)$"))
		end
		term.SetCaretPos(term.GetLength())
	end
end

-- see if the file exists
local function file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

local function addLog(logFile,text)
	if logFile then
		local f
		-- If file exists then append information
		if file_exists(logFile) then
			f = io.open(logFile,"a")
		else
			f = io.open(logFile,"w")
		end
		f:write(text)
		f:close()
	end
end

-- Executes the string cmd using a coroutine. Does not append the cmd to the terminal
-- If nohist is true then the command is not added to the history
local function execCmd(term,cmd,log,nohist)
	local stat,err, redirectIO
	--print("In execmd",cmd,nohist,term.data.co)
	-- Check if cmd goes to already executing script or its a new chunk
	if not term.data.co then
		-- Check if command is incomplete
		if incomplete(cmd) then
			--print("Incomplete command")
			term.Append("\n\t")
			term.SetCaretPos(term.GetLength())
			trimText(term)
			return
		else
			-- Execute the command here
			term.Append("\n")
			local f
			f,err = load(cmd,"=stdin","bt",term.data.env)
			if not f then
				term.Append(err.."\n>")
				-- Add cmd to command history
				if cmd ~= term.data.history[#term.data.history] then
					term.data.history[#term.data.history + 1] = cmd
					term.data.history[0] = #term.data.history+1
				end
				addLog(term.data.logFile,term.Get():sub(term.GetCaretPos()+2,-1))
				trimText(term)
				-- Update the prompt position
				term.data.prompt = term.GetLength()-offset
				term.SetCaretPos(term.GetLength())
				return
			else
				-- Add cmd to command history
				if not nohist and cmd ~= term.data.history[#term.data.history] then
					term.data.history[#term.data.history + 1] = cmd
					term.data.history[0] = #term.data.history+1
				end
				--print("Create coroutine for command",cmd)
				term.data.co = coroutine.create(f)
				stat,err = coroutine.resume(term.data.co)
			end
		end
	else
		--print("Use cmd as user input and resume coroutine",cmd)
		term.Append("\n")
		term.SetCaretPos(term.GetLength())
		stat,err = coroutine.resume(term.data.co,cmd)
	end
	--print(stat,err)
	if not stat then
		term.Append(err.."\n")
	elseif err == "UI" then
		--print("Need to get user input")
		-- Code needs user input through io.read so the input till the next enter goes to this coroutine
		redirectIO = true
	end
	if not redirectIO then
		term.data.co = nil	-- destroy the coroutine
		term.Append(">")
	end
	if log then
		local promptPos = term.data.prompt
		addLog(term.data.logFile,term.Get():sub(promptPos+2,-1))
	end
	trimText(term)
	-- Update the prompt position
	term.data.prompt = term.GetLength()-offset
	--print("Post execCmd",term.data.prompt,term.GetLength(),#term.Get(),offset)
	--print(term.Get():sub(1,term.data.prompt))
	--print("prompt: ",term.data.prompt[1],term.data.prompt[2])
	term.SetCaretPos(term.GetLength())
	--print("Ending execmd",term.data.co)
end

local function SetupKeywords(editor, useLuaParser)
    if useLuaParser then
        editor:SetLexer(wxstc.wxSTC_LEX_LUA)

        -- Note: these keywords are shamelessly ripped from scite 1.68
        editor:SetKeyWords(0,
            [[and break do else elseif end false for function if
            in local nil not or repeat return then true until while]])
        editor:SetKeyWords(1,
            [[_VERSION assert collectgarbage dofile error gcinfo loadfile loadstring
            print rawget rawset require tonumber tostring type unpack]])
        editor:SetKeyWords(2,
            [[_G getfenv getmetatable ipairs loadlib next pairs pcall
            rawequal setfenv setmetatable xpcall
            string table math coroutine io os debug
            load module select]])
        editor:SetKeyWords(3,
            [[string.byte string.char string.dump string.find string.len
            string.lower string.rep string.sub string.upper string.format string.gfind string.gsub
            table.concat table.foreach table.foreachi table.getn table.sort table.insert table.remove table.setn
            math.abs math.acos math.asin math.atan math.atan2 math.ceil math.cos math.deg math.exp
            math.floor math.frexp math.ldexp math.log math.log10 math.max math.min math.mod
            math.pi math.pow math.rad math.random math.randomseed math.sin math.sqrt math.tan
            string.gmatch string.match string.reverse table.maxn
            math.cosh math.fmod math.modf math.sinh math.tanh math.huge]])
        editor:SetKeyWords(4,
            [[coroutine.create coroutine.resume coroutine.status
            coroutine.wrap coroutine.yield
            io.close io.flush io.input io.lines io.open io.output io.read io.tmpfile io.type io.write
            io.stdin io.stdout io.stderr
            os.clock os.date os.difftime os.execute os.exit os.getenv os.remove os.rename
            os.setlocale os.time os.tmpname
            coroutine.running package.cpath package.loaded package.loadlib package.path
            package.preload package.seeall io.popen
            debug.debug debug.getfenv debug.gethook debug.getinfo debug.getlocal
            debug.getmetatable debug.getregistry debug.getupvalue debug.setfenv
            debug.sethook debug.setlocal debug.setmetatable debug.setupvalue debug.traceback]])

        -- Get the items in the global "wx" table for autocompletion
        if not wxkeywords then
            local keyword_table = {}
            for index, value in pairs(wx) do
                table.insert(keyword_table, "wx."..index.." ")
            end

            table.sort(keyword_table)
            wxkeywords = table.concat(keyword_table)
        end

        editor:SetKeyWords(5, wxkeywords)
    else
        editor:SetLexer(wxstc.wxSTC_LEX_NULL)
        editor:SetKeyWords(0, "")
    end

    editor:Colourise(0, -1)
end


-- Callback when backspace pressed
local function k_any(term,event)
	local caret = term.GetCaretPos()
	local c = event:GetKeyCode()
	--print("Key pressed",c,wx.WXK_BACK,caret,term.data.prompt)
	-- ignore Backspace pressed just after the current prompt
	if c==wx.WXK_BACK then
		if caret <= term.data.prompt then
			return
		end
		event:Skip()	-- Default handling
	elseif c==wx.WXK_RETURN then
		-- Execute the current text
		local promptPos = term.data.prompt
		local cmd = term.Get():sub(promptPos+1,-1)
		--print("new text is: ",cmd)
		term.executing = true	-- Mark execution has started
		term:execCmd(cmd,true)
		term.executing = nil
	elseif event:ControlDown() then
		if c==wx.WXK_UP then		-- up arrow pressed
			-- Go to the previous command in the history if cntrl is pressed
			if term.data.history[0] > 0 then
				term.data.history[0] = term.data.history[0] - 1
				if term.data.history[0] < 1 then
					term.data.history[0] = 1
				end
				local promptPos = term.data.prompt
				local cmd = term.data.history[term.data.history[0]]
				term.Set(term.Get():sub(1,promptPos)..cmd)
				term.SetCaretPos(term.GetLength())
			end
		elseif c==wx.WXK_LEFT then	-- left arrow pressed
			-- Go to the first command in the history if cntrl is pressed
			if term.data.history[0] > 0 then
				term.data.history[0] = 1
				local promptPos = term.data.prompt
				local cmd = term.data.history[term.data.history[0]]
				term.Set(term.Get():sub(1,promptPos)..cmd)
				term.SetCaretPos(term.GetLength())
			end
		elseif c==wx.WXK_RIGHT then	-- right arrow pressed
			-- Go to the last command in the history if cntrl is pressed
			if term.data.history[0] > 0 then
				term.data.history[0] = #term.data.history
				local promptPos = term.data.prompt
				local cmd = term.data.history[term.data.history[0]]
				term.Set(term.Get():sub(1,promptPos)..cmd)
				term.SetCaretPos(term.GetLength())
			end
		elseif c==wx.WXK_DOWN then	-- down arrow pressed
			-- Go to the next command in the history if cntrl is pressed
			if term.data.history[0] < #term.data.history+1 then
				term.data.history[0] = term.data.history[0] + 1
				local promptPos = term.data.prompt
				local cmd
				if term.data.history[0] > #term.data.history then
					cmd = ""
				else
					cmd = term.data.history[term.data.history[0]]
				end
				term.Set(term.Get():sub(1,promptPos)..cmd)
				term.SetCaretPos(term.GetLength())
			end
		else
			-- Default handling for other keys
			event:Skip()
		end
	else
        -- Default handling for other keys
        event:Skip()
	end
end

-- env is the environment associated with the terminal where the lua commands will be executed
-- logFile is the name if the logFile where the terminal output is backed up till the last executed command
-- redirectIO is a boolean, if true then print function and io.read and io.write (if they exist in the environment) will be redirected to use the text control
-- if redirectIO is true it returns the new versions of print and io.write to use in the host application to use the terminal as the output
function newTerm(parent,env,redirectIO, logFile)
	if not env then
		env = {}
	end
	local tenv = env
	-- Create the terminal multiline text control
	local term = {
		execCmd = execCmd
	}
	local prnt,iowrite,ioread,iprint,iiowrite,iioread
	if USESCINTILLA then
		term.term =  wxstc.wxStyledTextCtrl(parent, wx.wxID_ANY)
		local font,fontItalic
		-- Pick some reasonable fixed width fonts to use for the editor
		if wx.__WXMSW__ then
			font       = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_NORMAL, wx.wxFONTWEIGHT_NORMAL, false, "Consolas"--[["Andale Mono"]])
			fontItalic = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_ITALIC, wx.wxFONTWEIGHT_NORMAL, false, "Consolas"--[["Andale Mono"]])
		else
			font       = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_NORMAL, wx.wxFONTWEIGHT_NORMAL, false, "")
			fontItalic = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_ITALIC, wx.wxFONTWEIGHT_NORMAL, false, "")
		end
		
		local te = term.term
		
		-- Set up the styled text control
		--te:StyleClearAll()  -- Clear all styles
		--te:SetLexer(wxstc.wxSTC_LEX_LUA)  -- Set the lexer (optional)
		-- Terminal formatting
		
		te:SetBufferedDraw(true)
		te:StyleClearAll()

		te:SetFont(font)
		te:StyleSetFont(wxstc.wxSTC_STYLE_DEFAULT, font)
		for i = 0, 32 do
			te:StyleSetFont(i, font)
		end

		te:StyleSetForeground(0,  wx.wxColour(255, 255, 255)) -- White space
		te:StyleSetForeground(1,  wx.wxColour(0,   128, 0))   -- Block Comment
		te:StyleSetFont(1, fontItalic)
		--editor:StyleSetUnderline(1, false)
		te:StyleSetForeground(2,  wx.wxColour(0,   128, 0))   -- Line Comment
		te:StyleSetFont(2, fontItalic)                        -- Doc. Comment
		--editor:StyleSetUnderline(2, false)
		te:StyleSetForeground(3,  wx.wxColour(128, 0, 0)) -- Number
		te:StyleSetForeground(4,  wx.wxColour(0,   0, 255)) -- Keyword
		te:StyleSetForeground(5,  wx.wxColour(160,   20,   20)) -- Double quoted string
		te:StyleSetBold(5,  true)
		--editor:StyleSetUnderline(5, false)
		te:StyleSetForeground(6,  wx.wxColour(120, 0,   0)) -- Single quoted string
		te:StyleSetForeground(7,  wx.wxColour(127, 0,   127)) -- not used
		te:StyleSetForeground(8,  wx.wxColour(0,   0, 255)) -- Literal strings
		te:StyleSetForeground(9,  wx.wxColour(255, 0, 255))  -- Preprocessor
		te:StyleSetForeground(10, wx.wxColour(0,   0,   0))   -- Operators
		--editor:StyleSetBold(10, true)
		te:StyleSetForeground(11, wx.wxColour(0,   0,   0))   -- Identifiers
		te:StyleSetBold(11, true)
		te:StyleSetForeground(12, wx.wxColour(0,   128,  128))   -- Unterminated strings
		te:StyleSetBackground(12, wx.wxColour(224, 192, 224))
		te:StyleSetBold(12, true)
		te:StyleSetEOLFilled(12, true)

		te:StyleSetForeground(13, wx.wxColour(0,   0,  95))   -- Keyword 2 highlighting styles
		te:StyleSetForeground(14, wx.wxColour(0,   95, 0))    -- Keyword 3
		te:StyleSetForeground(15, wx.wxColour(127, 0,  0))    -- Keyword 4
		te:StyleSetForeground(16, wx.wxColour(127, 0,  95))   -- Keyword 5
		te:StyleSetForeground(17, wx.wxColour(35,  95, 175))  -- Keyword 6
		te:StyleSetForeground(18, wx.wxColour(0,   127, 127)) -- Keyword 7
		te:StyleSetBackground(18, wx.wxColour(240, 255, 255)) -- Keyword 8

		te:StyleSetForeground(19, wx.wxColour(0,   127, 127))
		te:StyleSetBackground(19, wx.wxColour(224, 255, 255))
		te:StyleSetForeground(20, wx.wxColour(0,   127, 127))
		te:StyleSetBackground(20, wx.wxColour(192, 255, 255))
		te:StyleSetForeground(21, wx.wxColour(0,   127, 127))
		te:StyleSetBackground(21, wx.wxColour(176, 255, 255))
		te:StyleSetForeground(22, wx.wxColour(0,   127, 127))
		te:StyleSetBackground(22, wx.wxColour(160, 255, 255))
		te:StyleSetForeground(23, wx.wxColour(0,   127, 127))
		te:StyleSetBackground(23, wx.wxColour(144, 255, 255))
		te:StyleSetForeground(24, wx.wxColour(0,   127, 127))
		te:StyleSetBackground(24, wx.wxColour(128, 155, 255))

		te:StyleSetForeground(32, wx.wxColour(224, 192, 224))  -- Line number
		te:StyleSetBackground(33, wx.wxColour(192, 192, 192))  -- Brace highlight
		te:StyleSetForeground(34, wx.wxColour(0,   0,   255))
		te:StyleSetBold(34, true)                              -- Brace incomplete highlight
		te:StyleSetForeground(35, wx.wxColour(255, 0,   0))
		te:StyleSetBold(35, true)                              -- Indentation guides
		te:StyleSetForeground(37, wx.wxColour(192, 192, 192))
		te:StyleSetBackground(37, wx.wxColour(255, 255, 255))

		te:SetUseTabs(false)
		te:SetTabWidth(4)
		te:SetIndent(4)
		te:SetIndentationGuides(true)

		te:SetVisiblePolicy(wxstc.wxSTC_VISIBLE_SLOP, 3)
		--editor:SetXCaretPolicy(wxstc.wxSTC_CARET_SLOP, 10)
		--editor:SetYCaretPolicy(wxstc.wxSTC_CARET_SLOP, 3)

		te:SetMarginWidth(0, te:TextWidth(32, "99999_")) -- line # margin

		te:SetMarginWidth(1, 16) -- marker margin
		te:SetMarginType(1, wxstc.wxSTC_MARGIN_SYMBOL)
		te:SetMarginSensitive(1, true)

		te:SetMarginWidth(2, 16) -- fold margin
		te:SetMarginType(2, wxstc.wxSTC_MARGIN_SYMBOL)
		te:SetMarginMask(2, wxstc.wxSTC_MASK_FOLDERS)
		te:SetMarginSensitive(2, true)

		te:SetFoldFlags(wxstc.wxSTC_FOLDFLAG_LINEBEFORE_CONTRACTED +
							wxstc.wxSTC_FOLDFLAG_LINEAFTER_CONTRACTED)

		te:SetProperty("fold", "1")
		te:SetProperty("fold.compact", "1")
		te:SetProperty("fold.comment", "1")
		
		
		term.Set = function(text)
			local st,stp = te:GetSelectionStart(),te:GetSelectionEnd()
			te:SetText(text)
			te:SetSelection(st,stp)
		end
		term.Append = function(text)
			--local st,stp = te:GetSelectionStart(),te:GetSelectionEnd()
			--print("Append:",st,stp)
			te:AppendText(text)
			te:SetSelection(-1,-1)
			--print("Append Post:",te:GetSelectionStart(),te:GetSelectionEnd())
		end
		term.GetLength = function()
			return te:GetTextLength()
		end
		term.Get = function()
			return te:GetText()
		end
		term.GetCaretPos = function()
			return te:GetCurrentPos()
		end
		term.SetCaretPos = function(pos)
			return te:SetCurrentPos(pos)
		end
		term.GetSelectedText = function()
			return te:GetSelectedText()
		end
		term.SetSelection = function(pos1,pos2)
			return te:SetSelection(pos1,pos2)
		end
		term.GetSelectionStart = function()
			return te:GetSelectionStart()
		end
		term.GetSelectionEnd = function()
			return te:GetSelectionEnd()
		end
		SetupKeywords(te,true)
		-- Bind the text modified event to the OnTextModified function
		te:Connect(wxstc.wxEVT_STC_MODIFIED, function(event) return action(term,event) end)
		-- Bind the key press event to the OnKeyPress function
		te:Connect(wx.wxEVT_KEY_DOWN, function(event) return k_any(term,event) end)
		--[=[
		iup.scintilla {
			appendnewline = "NO",
			expand = "YES",
			border = "NO",
			tabsize = 4,
			lexerlanguage = "lua",
			keywords0 = "and break do else elseif end false for function goto if in local nil not or repeat return then true until while",
			keywords1 = "print table string io coroutine table.unpack",
			stylefont32 = "Consolas",
			stylefontsize32 = "11",
			--styleclearall = "Yes",
			stylefgcolor1 = "0 128 0",	-- 1 Lua cooment
			stylefgcolor2 = "0 128 0",	-- 2 Lua comment line
			stylefgcolor4 = "128 0 0",	-- 4 Number
			stylefgcolor5 = "0 0 255",	-- 5 Keyword
			stylefgcolor6 = "160 20 20", -- 6 String
			stylefgcolor7 = "128 0 0",	-- 7 Character
			stylefgcolor9 = "0 0 255",	-- 9 Preprocessor block
			stylefgcolor10 = "255 0 255", -- 10 Operator
			--stylefgcolor11 = "0 255 0",	-- 11 Identifier
			stylefgcolor13 = "0 128 128",		-- Keyword set number 2
			stylebold10 = "YES",
			marginwidth0 = "50"		
		}
		]=]
	else
		offset = 0
		term.term = wx.wxTextCtrl(parent, wx.wxID_ANY, "", wx.wxDefaultPosition, wx.wxDefaultSize, wx.wxTE_MULTILINE)
		local te = term.term
		term.Set = function(text)
			te:Freeze()
			local st,stp = te:GetSelection()
			te:SetValue(text)
			te:SetSelection(st,stp)
			te:Thaw()
		end
		term.Append = function(text)
			--local st,stp = te:GetSelectionStart(),te:GetSelectionEnd()
			--print("Append:",st,stp)
			te:Freeze()
			te:AppendText(text)
			te:SetSelection(-1,-1)
			te:Thaw()
			--print("Append Post:",te:GetSelectionStart(),te:GetSelectionEnd())
		end
		-- Function to convert a position in the GetValue return to a position of the Get/SetInsertionPoint
		local function posValue2posCaret(pos)
			if te:GetLastPosition() ~= #te:GetValue() then
				local _,ln = te:GetValue():sub(1,pos):gsub("\n","") 
				pos = pos + ln -- Add 1 char for each line
			end			
			return pos
		end
		local function posCaret2posValue(pos)
			if te:GetLastPosition() ~= #te:GetValue() then
				local text = te:GetValue():gsub("\n","\r\n"):sub(1,pos)
				local _,ln = text:gsub("\n","")
				pos = pos - ln
			end			
			return pos
		end
		term.GetLength = function()
			--return te:GetLastPosition()
			return #te:GetValue()
			--return #te:GetRange(0,te:GetLastPosition())+1
		end
		term.Get = function()
			--return te:GetRange(0,te:GetLastPosition())
			return te:GetValue()
		end
		term.GetCaretPos = function()
			local pos = te:GetInsertionPoint()
			return posCaret2posValue(pos)
		end
		term.SetCaretPos = function(pos)
			pos = posValue2posCaret(pos)
			return te:SetInsertionPoint(pos)
		end
		term.GetSelectedText = function()
			return te:GetSelectedText()
		end
		term.SetSelection = function(pos1,pos2)
			return te:SetSelection(posValue2posCaret(pos1),posValue2posCaret(pos2))
		end
		term.GetSelectionStart = function()
			local st,stp = te:GetSelection()
			return posCaret2posValue(st)
		end
		term.GetSelectionEnd = function()
			local st,stp = te:GetSelection()
			return posCaret2posValue(stp)
		end
		-- Bind the text modified event to the OnTextModified function
		te:Connect(wx.wxEVT_TEXT, function(event) return action(term,event) end)
		-- Bind the key press event to the OnKeyPress function
		te:Connect(wx.wxEVT_KEY_DOWN, function(event) return k_any(term,event) end)
		
		--[[
		iup.text {
			appendnewline = "NO",
			multiline = "YES",
			expand = "YES",
			border = "NO",
			tabsize = 4,
			font = "Courier, 10",
			fgcolor = "0 150 150"
		}
		]]
	end
	if redirectIO then
		local doPrint,doiowrite
		-- Generate the print, io.write and io.read functions that can be used by scripts to use the terminal
		-- Modify the print statement
		prnt = function(...)
			-- 1st get whatever was written on the terminal so that remains for the user
			local promptPos = term.data.prompt
			local cmd = term.Get():sub(promptPos+1,-1)
			--print(cmd)
			if not term.executing then
				-- Remove whatever was written until the prompt
				term.Set(term.Get():sub(1,promptPos))
			end
			local t = table.pack(...) -- used this to get the nil parameters as well
			for i = 1,t.n do
				if i > 1 then
					term.Append("\t")
				end
				term.Append(tostring(t[i]))
			end
			term.Append("\n")
			if not term.executing then
				-- Now place the prompt and cmd in the end
				term.Append(">")
				-- Update the prompt position
				term.data.prompt = term.GetLength()-offset
				term.Append(cmd)
			end
			term.SetCaretPos(term.GetLength())
		end

		if env.print then
			doPrint = true
			-- The print function in the terminal is slightly different than the above since the command should not be copied down
			iprint = function(...)
				local t = table.pack(...) -- used this to get the nil parameters as well
				for i = 1,t.n do
					if i > 1 then
						term.Append("\t")
					end
					term.Append(tostring(t[i]))
				end
				term.Append("\n")
				term.SetCaretPos(term.GetLength())
			end
		end
		-- modify io.write and io.read
		iowrite = function(...)
			-- 1st get whatever was written on the terminal so that remains for the user
			local promptPos = term.data.prompt
			local cmd = term.Get():sub(promptPos+1,-1)
			--print("We are here")
			--print(cmd)
			if not term.executing then
				-- Remove whatever was written until the prompt
				term.Set(term.Get():sub(1,promptPos-1))
			end
			local t = table.pack(...)
			for i = 1,t.n do
				term.Append(tostring(t[i]))
			end
			if not term.executing then
				-- Update the prompt position
				term.Append("\n>")
				term.data.prompt = term.GetLength()-offset
				term.Append(cmd)
			end
			term.SetCaretPos(term.GetLength())
		end
		-- Modify the io.read
		ioread = function()
			local var = 1
			while env["_VARX"..var] do
				var = var + 1
			end
			--print("Variable number",var,term.data.co)
			local co,exec = term.data.co,term.executing
			term.data.co = nil
			term.executing = true	-- Mark execution has started
			term:execCmd("_VARX"..var.."=io.read()",nil,true)	-- Do not store in the history
			-- Now we need to transfer control to iup to process the LuaTerminal GUI till we get the input
			while not env["_VARX"..var] do
				wx.wxGetApp():Yield()
			end
			term.executing = exec
			--print("Execution finished")
			local value = env["_VARX"..var]
			env["_VARX"..var] = nil
			term.data.co = co
			return value
		end
		if env.io and type(env.io) == "table" then
			doiowrite = true
			-- modify io.write
			-- The io.write function in the terminal is slightly different in that it does not copy the command down
			iiowrite = function(...)
				local t = table.pack(...)
				for i = 1,t.n do
					term.Append(tostring(t[i]))
				end
				term.SetCaretPos(term.GetLength())
			end
			-- modify io.read
			iioread = function()
				--print("in iioread")
				local inp = coroutine.yield("UI")	-- To indicate it needs to read user input
				--print("iioread yield returned")
				return inp
			end
		end
		-- Create a cover layer on the environment
		if doPrint or doiowrite then
			local meta = {
				__index = function(t,k)
					if k == "print" and doPrint then
						return iprint
					elseif k == "io" and doiowrite then
						local t = {}
						local tmeta = {
							__index = function(t,k)
								if k == "write" then
									return iiowrite
								elseif k == "read" then
									return iioread
								else
									return env.io[k]
								end
							end,
							__newindex = function(t,k,v)
								env.io[k] = v
							end
						}
						return setmetatable(t,tmeta)
					else
						return env[k]
					end
				end,
				__newindex = function(t,k,v)
					--print("LuaTerminal: ",t,k,v)
					env[k] = v
				end
			}
			tenv = setmetatable({},meta)
		end
	end		-- if redirectIO then ends
	term.data = {
		history = {[0] = 0},	-- To store the command history, index 0 contains the command pointer
		env = tenv,		-- The environment where the scripts are executed
		logFile = logFile, 	-- Where all the terminal text is written to
		maxText = MAXTEXT,	-- Maximum number of characters in the text box
		prompt = term.GetLength()		-- current position of the prompt to prevent it from being deleted
	}
	
	-- Display the start message
	term.SetSelection(-1,-1)
	--print("Before adding",term.GetSelectionStart(),term.GetSelectionEnd())
	term.Append("LuaTerminal version ".._VERSION.."\n")
	-- Display the prompt
	term.Append(">")
	term.data.prompt = term.GetLength()-offset
	term.SetCaretPos(term.GetLength())
	
	numOfTerms = numOfTerms + 1
	--print("Prompt at creation: ",term.data.prompt)
	return term,prnt,iowrite,ioread
end

-- To create a terminal on a socket to allow remote connection by other applications
-- env is the environment associated with the terminal where the lua commands will be executed
-- logFile is the name if the logFile where the terminal output is backed up till the last executed command
-- redirectIO is a boolean, if true then print function and io.read and io.write will be redirected to use the text control
function newSocketTerm(env,redirectIO,logFile)
	socket = require("socket")
	local s,msg = socket.bind("*", 0)
	if not s then
		return nil,msg
	end
	s:settimeout(0.001)	-- Time out of 1 millisecond
	local ip,port = s:getsockname()
	local c,sockTerm, cmd, SPMSG
	
	SPMSG = "LUATERMINAL@"..tostring(port).."@"..tostring(M)
	sockCR = SPMSG
	local timer
	sockTerm = {
		history = {[0] = 0},	-- To store the command history, index 0 contains the command pointer
		env = env,		-- The environment where the scripts are executed
		timer = timer,
		logFile = logFile 	-- Where all the terminal text is written to
	}

	if redirectIO then
		-- Modify the print statement
		if env.print then
			env.print = function(...)
				local t = table.pack(...)
				local str = ""
				for i = 1,t.n do
					if i > 1 then
						str = str.."\t"
					end
					str = str..tostring(t[i])
				end
				c:send(str..sockCR.."\n")
				addLog(sockTerm.logFile,str.."\n")
			end
		end
		-- modify io.write and io.read
		if env.io and type(env.io) == "table" then
			-- modify io.write
			env.io.write = function(...)
				local t = table.pack(...)
				local str = ""
				for i = 1,t.n do
					str = str..tostring(t[i])
				end
				c:send(str.."\n")
				addLog(sockTerm.logFile,str)
			end
			-- modify io.read
			env.io.read = function()
				local inp = coroutine.yield("UI")	-- To indicate it needs to read user input
				return inp
			end
		end

	end
	-- Function to return a function that multicasts/broadcasts the ip and port
	local function broadcastIPFunc()
		--create udp instance for broadcasting.multicasting
		local send = socket.udp()
		--set timeout so it won't block UI
		send:settimeout(0)
		
		return function()
			--message we will send
			local msg = SPMSG		-- Send a unique identifier

			--first we send to multicast group
			--multicast IP range from 224.0.0.0 to 239.255.255.255
			--we simple select on and use the same in clients' code
			send:sendto(msg, "239.192.1.1", 11111)

			--then we enable broadcast option
			local done = send:setoption('broadcast', true)
			if done then
				--and broadcast the message
				--global broadcast address is 255.255.255.255
				send:sendto(msg, "255.255.255.255", 11111)
				--and we disable broadcast option
				send:setoption('broadcast', false)
			end
		end
	end
	
	local broadcastIP = broadcastIPFunc()
	
	cmd = ""
	local function timer_action()
		--print("Come on!")
		--print(c,sockTerm.closed)
		local line,err, stat,redirectIO
		timer:Stop()	-- Stop the timer
		if not c and not sockTerm.closed then	-- If nothing connected and a previous connection closed not there then
			-- Broadcast ip and port to anyone listening
			--print("Broadcast IP")
			broadcastIP()
			c,msg = s:accept()
			if c then
				c:settimeout(0)
			end
		end
		if c then
			--print("Already connected")
			line,err = c:receive()	-- Receive a line from the connected client
			msg = ""	-- Response message back to socket
			if line and line ~= "" then
				if line:sub(1,#SPMSG) == SPMSG then
					-- This is a special command
					line = line:sub(#SPMSG+1,-1)
					if line:sub(1,2) == "UP" then
						-- Return the previous command
						if sockTerm.history[0] > 0 then
							sockTerm.history[0] = sockTerm.history[0] - 1
							if sockTerm.history[0] < 1 then
								sockTerm.history[0] = 1
							end
							c:send(sockTerm.history[sockTerm.history[0]]:gsub("\n",SPMSG).."\n")
						end
					elseif line:sub(1,4) == "DOWN" then
						-- return the next command
						if sockTerm.history[0] < #sockTerm.history+1 then
							sockTerm.history[0] = sockTerm.history[0] + 1
							if sockTerm.history[0] > #sockTerm.history then
								c:send("\n")
							else
								c:send(sockTerm.history[sockTerm.history[0]]:gsub("\n",SPMSG).."\n")
							end
						end
					elseif line:sub(1,4) == "LEFT" then
						-- return the 1st command
						if sockTerm.history[0] > 0 then
							sockTerm.history[0] = 1
							c:send(sockTerm.history[sockTerm.history[0]]:gsub("\n",SPMSG).."\n")
						end
					elseif line:sub(1,5) == "RIGHT" then
						-- Return the last command
						if sockTerm.history[0] > 0 then
							sockTerm.history[0] = #sockTerm.history
							c:send(sockTerm.history[sockTerm.history[0]]:gsub("\n",SPMSG).."\n")
						end
					end
				else
					cmd = cmd..line
					if not sockTerm.co then	-- check if a coroutine is already in process
						-- Check if command is incomplete
						if incomplete(cmd) then
							cmd = cmd.."\n\t"
							stat,err = c:send(SPMSG.."\n")
							if not stat and err == "closed" then
								c = nil
								sockTerm.closed = true
							end
							timer:Start(10)	-- Restart the timer
							return
						else
							-- Execute the command here
							local f
							f,err = load(cmd,"=stdin","bt",sockTerm.env)
							if not f then
								-- Add cmd to command history
								if cmd ~= sockTerm.history[#sockTerm.history] then
									sockTerm.history[#sockTerm.history + 1] = cmd
									sockTerm.history[0] = #sockTerm.history+1
								end
								addLog(sockTerm.logFile,cmd.."\n"..err.."\n")
								cmd = ""	-- refresh the command
								stat,err = c:send(err..sockCR.."\n")
								if not stat and err == "closed" then
									c = nil
									sockTerm.closed = true
								end
								timer:Start(10)	-- Restart the timer
								return
							else
								addLog(sockTerm.logFile,cmd.."\n")
								-- Add cmd to command history
								if cmd ~= sockTerm.history[#sockTerm.history] then
									sockTerm.history[#sockTerm.history + 1] = cmd
									sockTerm.history[0] = #sockTerm.history+1
								end
								sockTerm.co = coroutine.create(f)
								stat,err = coroutine.resume(sockTerm.co)
							end
						end
					else
						-- Coroutine was already in process. Pass the received data into it.
						addLog(sockTerm.logFile,cmd.."\n")
						stat,err = coroutine.resume(sockTerm.co,cmd)
					end
					if not stat then
						msg = err.."\n"
						stat,err = c:send(err..sockCR.."\n")
						if not stat and err == "closed" then
							c = nil
							sockTerm.closed = true
						end
					elseif err == "UI" then
						-- Code needs user input through io.read so the input till the next enter goes to this coroutine
						redirectIO = true
					end
					if not redirectIO then
						sockTerm.co = nil	-- destroy the coroutine
					end
					addLog(sockTerm.logFile,msg)
					cmd = ""
				end		-- if line:sub(1,#SPMSG) = SPMSG then ends
			elseif not line and err == "closed" then
				-- Connection closed
				c = nil
				sockTerm.closed = true
			end		-- if line then ends
		end		-- if c then ends
		timer:Start(10)	-- Restart the timer
	end		-- function timer:action_cb() ends
	numOfSockTerms = numOfSockTerms + 1
	-- Setup timer to run housekeeping
	-- Frame to host the timer
	local frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "Timer Example", wx.wxDefaultPosition, wx.wxSize(300, 200))	
	timer = wx.wxTimer(frame)
	-- Connect the timer event to the OnTimer function
	frame:Connect(timer:GetId(), wx.wxEVT_TIMER, timer_action)
	timer:Start(10)
	return sockTerm
end