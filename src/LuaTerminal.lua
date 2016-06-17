----------------------------------------------
-- Lua Terminal Module
-- Supports multiple terminals with independent command histories
-- @module LuaTerminal
-- @dependency iup
-- @dependency luasocket if terminal over socket is created
-- @date 9/3/2014

local iup = iup

local type = type
local tonumber = tonumber
local tostring = tostring
local load = load
local coroutine = coroutine
local io = io
local require = require
local table = table

-- For debugging
local print = print
--local pairs = pairs

-- Create the module table here
local M = {}
package.loaded[...] = M
_ENV = M		-- Lua 5.2+

-- Create the module table ends

_VERSION = "1.16.06.16"
MAXTEXT = 8192		-- maximum characters in text box
USESCINTILLA = false

local numOfTerms = 0	-- To maintain the number of terminals being managed
local numOfSockTerms = 0	-- To maintain the number of socket terminals being managed
local socket
local sockCR = "@#"
local offset = 0	-- Offset to the row and column indexes in case scintilla is used

-- Check some iup things to see if it is really loaded
if not iup or type(iup) ~= "table" or not iup.GetGlobal or type(iup.GetGlobal) ~= "function" or not iup.text or type(iup.text) ~= "function" then
	package.loaded[...] = nil
	return nil, "iup should be loaded in the global iup variable before loading the module."
end

if USESCINTILLA and not iup.scintilla or type(iup.scintilla) ~= "function" then
	package.loaded[...] = nil
	return nil, "iup scintilla should be loaded if USESCINTILLA is set to true."
end

-- Function called when terminal is mapped
local function map_cb(term)
	if USESCINTILLA then
		offset = 1
	end
	if term.data.prompt[1] == 0 and term.data.prompt[2] == 0 then
		-- Display the start message
		term.append = "LuaTerminal version ".._VERSION.."\n"
		-- Display the prompt
		term.append = ">"
		term.data.prompt = {2-offset,1-offset}
		term.caretpos = #term.value
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

-- Function to trim the text in the beginning of the terminal to keep the terminal content within the MAXLENGTH
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
		term.caretpos = #term.value-offset
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
				term.caretpos = #term.value
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
					addLog(term.data.logFile,term.value:sub(promptPos+2,-1))
					trimText(term)
					-- Update the prompt position
					term.data.prompt[1],term.data.prompt[2] = iup.TextConvertPosToLinCol(term, #term.value-1)
					term.caretpos = #term.value
					return iup.IGNORE
				else
					-- Add cmd to command history
					if cmd ~= term.data.history[#term.data.history] then
						term.data.history[#term.data.history + 1] = cmd
						term.data.history[0] = #term.data.history+1
					end
					term.data.co = coroutine.create(f)
					stat,err = coroutine.resume(term.data.co)
				end
			end
		else
			term.append = "\n"
			term.caretpos = #term.value
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
		end
		addLog(term.data.logFile,term.value:sub(promptPos+2,-1))
		trimText(term)
		-- Update the prompt position
		term.data.prompt[1],term.data.prompt[2] = iup.TextConvertPosToLinCol(term, #term.value-1)
		--print("prompt: ",term.data.prompt[1],term.data.prompt[2])
		term.caretpos = #term.value
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
function newTerm(env,redirectIO, logFile)
	if not env then
		env = {}
	end
	-- Create the terminal multiline text control
	local term 
	if USESCINTILLA then
		term = iup.scintilla {
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
	else
		term = iup.text {
			appendnewline = "NO",
			multiline = "YES",
			expand = "YES",
			border = "NO",
			tabsize = 4,
			font = "Courier, 10",
			fgcolor = "0 150 150"
		}
	end
	term.map_cb = map_cb
	term.k_any = k_any
	term.action = action
	if redirectIO then
		-- Modify the print statement
		if env.print then
			env.print = function(...)
				local t = table.pack(...) -- used this to get the nil parameters as well
				for i = 1,t.n do
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
				local t = table.pack(...)
				for i = 1,t.n do
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

-- To create a terminal on a socket to allow remote connection by other applications
-- env is the environment associated with the terminal where the lua commands will be executed
-- logFile is the name if the logFile where the terminal output is backed up till the last executed command
-- redirectIO is a boolean, if true then print function and io.read and io.write will be redirected to use the text control
function newSocketTerm(env,redirectIO,logFile)
	socket = require("socket")
	-- Setup timer to run housekeeping
	local timer = iup.timer{time = 10, run = "NO"}	-- run timer with every 10ms action
	local s,msg = socket.bind("*", 0)
	if not s then
		return nil,msg
	end
	s:settimeout(0.001)	-- Time out of 1 millisecond
	local ip,port = s:getsockname()
	local c,sockTerm, cmd, SPMSG
	
	SPMSG = "LUATERMINAL@"..tostring(port).."@"..tostring(M)
	sockCR = SPMSG
	
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
				str = ""
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
	function timer:action_cb()
		--print("Come on!")
		--print(c,sockTerm.closed)
		local line,err, stat,redirectIO
		timer.run = "NO"	-- Stop the timer
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
							timer.run = "YES"	-- Restart the timer
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
								timer.run = "YES"	-- Restart the timer
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
		timer.run = "YES"	-- Restart the timer
	end		-- function timer:action_cb() ends
	numOfSockTerms = numOfSockTerms + 1
	timer.run = "YES"
	return sockTerm
end