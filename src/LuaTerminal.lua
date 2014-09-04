----------------------------------------------
-- Lua Termina Module
-- Supports multiple terminals with independent command histories
-- @module LuaTerminal
-- @dependencies iup
-- @date 9/3/2014

local iup = iup

local type = type
local tonumber = tonumber

-- For debugging
local print = print

-- Create the module table here
local M = {}
package.loaded[...] = M
if setfenv then
	setfenv(1,M)	-- Lua 5.1
else
	_ENV = M		-- Lua 5.2
end
-- Create the module table ends

_VERSION = "1.2014.09.03"

-- Check some iup things to see if it is really loaded
if type(iup) ~= "table" or not iup.GetGlobal or type(iup.GetGlobal) ~= "function" or not iup.text or type(iup.text) ~= "function" then
	return nil, "iup should be loaded in the global iup variable before loading the module."
end

-- Function called when terminal is mapped
local function map_cb(term)
	if term.data.text == "" then
		-- Display the prompt
		term.append = ">"
		term.data.prompt = {1,1}
	end
end

-- Callback when backspace pressed
local function k_any(term,c)
	if c==iup.K_BS then
		print("Backspace pressed", term.caret,c)
		local caret = term.caret
		if tonumber(caret:match("(.-),.+")) == term.data.prompt[1] and tonumber(caret:match(".-,(.+)")) == term.data.prompt[2] + 1 then
			return iup.IGNORE
		end
	else
		return iup.DEFAULT
	end
end

function new(env)
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
	term.data = {
		history = {},	-- To store the command history
		text = "",
		env = env,		-- The environment where the scripts are executed
		formatting = {},		-- To store all formatting applied to the 
		prompt = {0,0}		-- current position of the prompt to prevent it from being deleted
	}
	
	return term
end

