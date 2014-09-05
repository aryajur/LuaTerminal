----------------------------------------------
-- Lua Terminal Module
-- Supports multiple terminals with independent command histories
-- @module LuaTerminal
-- @dependencies iup
-- @date 9/3/2014

local iup = iup

local type = type
local tonumber = tonumber
local tostring = tostring
local load = load
local coroutine = coroutine
local io = io

-- For debugging
--local print = print

-- Create the module table here
local M = {}
package.loaded[...] = M
_ENV = M		-- Lua 5.2

-- Create the module table ends

_VERSION = "1.2014.09.05"
MAXTEXT = 8192		-- maximum characters in text box

local numOfTerms = 0	-- To maintain the number of terminals being managed

-- Check some iup things to see if it is really loaded
if type(iup) ~= "table" or not iup.GetGlobal or type(iup.GetGlobal) ~= "function" or not iup.text or type(iup.text) ~= "function" then
	return nil, "iup should be loaded in the global iup variable before loading the module."
end

-- Function called when terminal is mapped
local function map_cb(term)
	if term.data.prompt[1] == 0 and term.data.prompt[2] == 0 then
		-- Display the prompt
		term.append = ">"
		term.data.prompt = {1,1}
	end
end

local incomplete = function (str)
	local f, err = load(str)
	return f == nil and (err:find(" expected .*near <eof>$") or err:find(" unexpected symbol near <eof>$") or err:find(" syntax error near <eof>$"))
end

local function action(term,c,newVal)
	local caret = term.caret
	local selection = term.selection
--	print("action generated")
--	print("caret: ",caret)
--	print("selection: ", selection)
	-- Ignore any editing done before the current prompt
	if tonumber(caret:match("^(.-),.+")) < term.data.prompt[1] then
		return iup.IGNORE
	end
	if tonumber(caret:match("^(.-),.+")) == term.data.prompt[1] and tonumber(caret:match("^.-,(.+)")) <= term.data.prompt[2] then
		return iup.IGNORE
	end
	if selection then
		if tonumber(selection:match("^(.-),.+")) < term.data.prompt[1] then
			return iup.IGNORE
		end
		if tonumber(selection:match("^(.-),.+")) == term.data.prompt[1] and tonumber(selection:match("^.-,(.-):.+")) <= term.data.prompt[2] then
			return iup.IGNORE
		end
	end
	return iup.DEFAULT
end

-- Function to trim the text in the beginning of the terminal
local function trimText(term)
	--print(#term.value,term.data.maxText,term.value)
	if #term.value > term.data.maxText then
		--print(term.value:sub(-term.data.maxText,-1))
		-- Trim it justified with a line feed
		if term.value:sub(-term.data.maxText-1,-term.data.maxText-1) == "\n" then
			term.value = term.value:sub(-term.data.maxText,-1)
		else
			term.value = term.value:sub(-term.data.maxText,-1):match(".-\n(.+)$")
		end
		term.caretpos = #term.value
	end
end

-- see if the file exists
function file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

local function addLog(term,text)
	if term.data.logFile then
		local f
		-- If file exists then append information
		if file_exists(term.data.logFile) then
			f = io.open(term.data.logFile,"a")
		else
			f = io.open(term.data.logFile,"w")
		end
		f:write(text)
		f:close()
	end
end

-- Callback when backspace pressed
local function k_any(term,c)
	local caret = term.caret
	-- ignore Backspace pressed just after the current prompt
	if c==iup.K_BS then
		if tonumber(caret:match("^(.-),.+")) < term.data.prompt[1] then
			return iup.IGNORE
		end
		if tonumber(caret:match("^(.-),.+")) == term.data.prompt[1] and tonumber(caret:match("^.-,(.+)")) <= term.data.prompt[2] + 1 then
			return iup.IGNORE
		end
		return iup.DEFAULT
	elseif c==iup.K_CR then
		local stat,err, redirectIO
		-- Execute the current text
		local promptPos = iup.TextConvertLinColToPos(term, term.data.prompt[1], term.data.prompt[2])
		local cmd = term.value:sub(promptPos+2,-1)
		--print("new text is: ",cmd)
		-- Check if cmd goes to already executing script or its a new chunk
		if not term.data.co then
			-- Check if command is incomplete
			if incomplete(cmd) then
				term.append = "\n\t"
				trimText(term)
				return iup.IGNORE
			else
				-- Execute the command here
				term.append = "\n"
				local f
				f,err = load(cmd,"=stdin","bt",term.data.env)
				if not f then
					term.append = err.."\n>"
					-- Add cmd to command history
					if cmd ~= term.data.history[#term.data.history] then
						term.data.history[#term.data.history + 1] = cmd
						term.data.history[0] = #term.data.history+1
					end
					addLog(term,term.value:sub(promptPos+2,-1))
					trimText(term)
					-- Update the prompt position
					term.data.prompt[1],term.data.prompt[2] = iup.TextConvertPosToLinCol(term, #term.value-1)
					return iup.IGNORE
				else
					term.data.co = coroutine.create(f)
					stat,err = coroutine.resume(term.data.co)
				end
			end
		else
			term.append = "\n"
			stat,err = coroutine.resume(term.data.co,cmd)
		end
		if not stat then
			term.append = err.."\n"
		elseif err == "UI" then
			-- Code needs user input through io.read so the input till the next enter goes to this coroutine
			redirectIO = true
		end
		if not redirectIO then
			term.data.co = nil	-- destroy the coroutine
			term.append = ">"
			-- Add cmd to command history
			if cmd ~= term.data.history[#term.data.history] then
				term.data.history[#term.data.history + 1] = cmd
				term.data.history[0] = #term.data.history+1
			end
		end
		addLog(term,term.value:sub(promptPos+2,-1))
		trimText(term)
		-- Update the prompt position
		term.data.prompt[1],term.data.prompt[2] = iup.TextConvertPosToLinCol(term, #term.value-1)
		--print("prompt: ",term.data.prompt[1],term.data.prompt[2])
		return iup.IGNORE
	elseif c==iup.K_cUP then		-- up arrow pressed
		-- Go to the previous command in the history if cntrl is pressed
		if term.data.history[0] > 0 then
			term.data.history[0] = term.data.history[0] - 1
			if term.data.history[0] < 1 then
				term.data.history[0] = 1
			end
			local promptPos = iup.TextConvertLinColToPos(term, term.data.prompt[1], term.data.prompt[2])
			local cmd = term.data.history[term.data.history[0]]
			term.value = term.value:sub(1,promptPos+1)..cmd
			term.caretpos = #term.value
		end
		return iup.IGNORE
	elseif c==iup.K_cLEFT then	-- left arrow pressed
		-- Go to the first command in the history if cntrl is pressed
		if term.data.history[0] > 0 then
			term.data.history[0] = 1
			local promptPos = iup.TextConvertLinColToPos(term, term.data.prompt[1], term.data.prompt[2])
			local cmd = term.data.history[term.data.history[0]]
			term.value = term.value:sub(1,promptPos+1)..cmd
			term.caretpos = #term.value
		end
		return iup.IGNORE
	elseif c==iup.K_cRIGHT then	-- right arrow pressed
		-- Go to the last command in the history if cntrl is pressed
		if term.data.history[0] > 0 then
			term.data.history[0] = #term.data.history
			local promptPos = iup.TextConvertLinColToPos(term, term.data.prompt[1], term.data.prompt[2])
			local cmd = term.data.history[term.data.history[0]]
			term.value = term.value:sub(1,promptPos+1)..cmd
			term.caretpos = #term.value
		end
		return iup.IGNORE	
	elseif c==iup.K_cDOWN then	-- down arrow pressed
		-- Go to the next command in the history if cntrl is pressed
		if term.data.history[0] < #term.data.history+1 then
			term.data.history[0] = term.data.history[0] + 1
			local promptPos = iup.TextConvertLinColToPos(term, term.data.prompt[1], term.data.prompt[2])
			local cmd
			if term.data.history[0] > #term.data.history then
				cmd = ""
			else
				cmd = term.data.history[term.data.history[0]]
			end
			term.value = term.value:sub(1,promptPos+1)..cmd
			term.caretpos = #term.value
		end
		return iup.IGNORE
	else
		return iup.DEFAULT
	end
end

-- env is the environment associated with the terminal where the lua commands will be executed
-- logFile is the name if the logFile where the terminal output is backed up till the last executed command
-- redirectIO is a boolean, if true then print function and io.read and io.write will be redirected to use the text control
function new(env,redirectIO, logFile)
	if not env then
		env = {}
	end
	-- Create the terminal multiline text control
	local term = iup.text {
		appendnewline = "NO",
		multiline = "YES",
		expand = "YES",
		border = "NO",
		font = "Dejavu Sans Mono, 10"
	}
	term.map_cb = map_cb
	term.k_any = k_any
	term.action = action
	if redirectIO then
		-- Modify the print statement
		if env.print then
			env.print = function(...)
				local t = {...}
				for i = 1,#t do
					if i > 1 then
						term.append = "\t"
					end
					term.append = tostring(t[i])
				end
				term.append = "\n"
			end
		end
		-- modify io.write and io.read
		if env.io and type(env.io) == "table" then
			-- modify io.write
			env.io.write = function(...)
				local t = {...}
				for i = 1,#t do
					term.append = tostring(t[i])
				end
			end
			-- modify io.read
			env.io.read = function()
				local inp = coroutine.yield("UI")	-- To indicate it needs to read user input
				return inp
			end
		end

	end
	term.data = {
		history = {[0] = 0},	-- To store the command history, index 0 contains the command pointer
		env = env,		-- The environment where the scripts are executed
		formats = {},		-- To store all formatting applied to the 
		logFile = logFile, 	-- Where all the terminal text is written to
		maxText = MAXTEXT,	-- Maximum number of characters in the text box
		prompt = {0,0}		-- current position of the prompt to prevent it from being deleted
	}
	
	numOfTerms = numOfTerms + 1
	
	return term
end

