-- Remote terminal

socket = require("socket")

local SPMSG

local function getServerIPinit()
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
		print("multicast not supported, opting for broadcast")
	    listen = socket.udp()
	    listen:setsockname("*", 11111)
	end
	 
	--set timeout so it won't block UI
	listen:settimeout(0)
	return listen
end

local listen = getServerIPinit()

print("look for server IP")

local function getServerIP(listen)
	repeat
		--try to get any data and sender's IP address
		local data, ip, port = listen:receivefrom()
		if data then
			print(data,ip,port)
		end
		--if there is data
		if data and data:sub(1,12) == "LUATERMINAL@" then
		    --we have a server trying to discover us
		    --it's IP address is stored in ip variable
			SPMSG = data
			port = tonumber(data:match("LUATERMINAL@(.-)@.+"))
			return ip, port
		end
		--repeat until there is no data to receive
	until not data
end

local serverIP,serverPort
-- Get the server IP
while(1) do
	serverIP, serverPort = getServerIP(listen)
	if serverIP then
		print("Got server IP:Port "..serverIP..":"..serverPort)
		break
	end
	--print("try again")
end

-- Now try connecting to the server
c = assert(socket.connect(serverIP, serverPort))
print("Connected! Please type stuff (empty line to stop):")
l = io.read()
c:settimeout(0.1)
while l and l ~= "" and not e do
	assert(c:send(l .. "\n"))
	--print("Now receiving:")
	repeat
		a = {c:receive("*l")}
		if a[1] then
			if a[1] == SPMSG then
				-- This indicates that the previous command was incomplete
				a[1] = "\t"
			elseif a[1]:sub(-(#SPMSG),-1) == SPMSG then
				a[1] = a[1]:sub(1,-(#SPMSG)-1).."\n"
			end
			io.write(a[1])
		end
	until not a[1]
	--print("receiving end")
	l = io.read()
end
