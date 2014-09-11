----------------------------------------------
-- Lua Terminal RemoteModule
-- Allows connecting to an open socket terminal by LuaTerminal
-- @module LuaTerminalRemote
-- @dependency luasocket
-- @date 9/10/2014

local tonumber = tonumber
local os = os
local socket = require("socket")

-- Create the module table here
local M = {}
package.loaded[...] = M
_ENV = M		-- Lua 5.2

_VERSION = "1.2014.09.10"

Connected = false	-- to indicate whether connection to LuaTerminal is there or not

local SPMSG, listen, termIP, termPort, client

local function getTerminalIPinit()
	--create udp instance fir listening broadcasts/multicasts
	local listen = socket.udp()
	 
	--try to set socket for multicast
	--multicast IP range from 224.0.0.0 to 239.255.255.255
	local err,msg = listen:setsockname("*", 11111)
	 
	--if supports
	if(err)then
	    --add interface to multicast
	    listen:setoption("ip-add-membership" ,
		{ multiaddr = "239.192.1.1", interface = "*"})
	else
	    --else set it's own IP address
	    --and will hope that broadcast messages work
		--print("multicast not supported, opting for broadcast")
	    listen = socket.udp()
	    listen:setsockname("*", 11111)
	end
	 
	--set timeout so it won't block UI
	listen:settimeout(0)
	return listen
end

local function getTerminalIP(listener)
	--try to get any data and sender's IP address
	local data, ip, port = listener:receivefrom()
	--if there is data
	if data and data:sub(1,12) == "LUATERMINAL@" then
		--we have a server trying to discover us
		--it's IP address is stored in ip variable
		SPMSG = data
		port = tonumber(data:match("LUATERMINAL@(.-)@.+"))
		return ip, port
	else
		return nil,ip
	end
end

listen = getTerminalIPinit()

function tryConnect(timeout,socketTimeout)
	if Connected then
		return Connected
	end
	if not timeout then
		timeout = 0.01
	end
	local err
	local start = os.clock()
	-- Get the server IP
	while(os.clock()-start < timeout) do
		termIP, termPort = getTerminalIP(listen)
		if termIP then
			client,err = socket.connect(termIP, termPort)
			if client then
				if socketTimeout and type(socketTimeout) == "number" then
					client:settimeout(socketTimeout)
				else
					client:settimeout(0.1)
				end
				Connected = {termIP,termPort}
				return Connected
			else
				return nil,err
			end
			--print("Got server IP:Port "..serverIP..":"..serverPort)
		end
		--print("try again")
	end
	return nil, "timeout"
end		-- function tryConnect(timeout) ends

function sendData(str)
	if client then
		local stat,err
		stat,err = client:send(str.."\n")
		if not stat and err == "closed" then
			Connected = false
			client = nil
		end
		return stat,err
	else
		return nil, "Not connected"
	end
end

function sendCMD(cmd)
	local ret,err
	sendData(SPMSG..cmd.."\n")
	ret,err = receiveData()
	while not ret and err~="closed" do
		ret = receiveData()
	end
	return ret
end

function sendUP()
	return sendCMD("UP")
end

function sendDOWN()
	return sendCMD("DOWN")
end

function sendLEFT()
	return sendCMD("LEFT")
end

function sendRIGHT()
	return sendCMD("RIGHT")
end

function receiveData()
	if client then
		local a,ret
		ret = nil
		--print("Now receiving:")
		repeat
			a = {client:receive("*l")}
			if a[1] then
				if a[1] == SPMSG then
					-- This indicates that the previous command was incomplete
					a[1] = "\t"
				elseif a[1]:find(SPMSG,1,true) then
					a[1] = a[1]:gsub(SPMSG,"\n")
				end
				if not ret then
					ret = a[1]
				else
					ret = ret..a[1]
				end
			end
		until not a[1]	-- Empty the receive buffer of all the data
		if a[2] == "closed" then
			Connected = false
			client = nil
			return nil,"closed"
		end
		return ret
	else
		return nil, "Not connected"
	end
end
