----------------------------------------------
-- Lua Termina Module
-- Supports multiple terminals with independent command histories
-- @module LuaTerminal
-- @dependencies iup
-- @date 9/3/2014

local iup = iup

local type = type

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

local data = {}		-- Table to store states of all opened terminals

-- Check some iup things to see if it is really loaded
if type(iup) ~= "table" or not iup.GetGlobal or type(iup.GetGlobal) ~= "function" or not iup.text or type(iup.text) ~= "function" then
	return nil, "iup should be loaded in the global iup variable before loading the module."
end

-- Function called when terminal is mapped
local function map_cb(term)
	if data[term].text == "" then
		-- Display the prompt
		term.append = ">"
		prompt = 0
	end
end

function new()
	-- Create the terminal multiline text control
	term = iup.text {
		appendnewline = "NO",
		multiline = "YES",
		expand = "YES",
		border = "NO",
		font = "Dejavu Sans Mono, 10"
	}
	term.map_cb = map_cb
	data[term] = {
		history = {},
		text = "",
		formatting = {},		-- To store all formatting applied to the 
		prompt = -1				-- current position of the prompt to prevent it from being deleted
	}
end

