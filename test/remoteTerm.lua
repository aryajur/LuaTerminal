-- To test LuaTerminal module

-- package.path = package.path..";./src/?.lua"	-- For Zerobrane
package.path = package.path..";./../src/?.lua"

rt = require("LuaTerminalRemote")

print("Try Connecting")
while(not rt.tryConnect()) do
end


print("Connected! Please type stuff (empty line to stop):")
l = io.read()
while l and l ~= "" do
	local rec
	if l:lower() == "up" then
		io.write(rt.sendUP())
	elseif l:lower() == "down" then
		io.write(rt.sendDOWN())
	elseif l:lower() == "left" then
		io.write(rt.sendLEFT())
	elseif l:lower() == "right" then
		io.write(rt.sendRIGHT())
	else
		rt.sendData(l)
		rec = rt.receiveData()
		if rec then
			io.write(rec)
		end
	end
	l = io.read()
end
