local skynet = require "skynet"
local socket = require "socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local table = table
local string = string


local mode = ...

if mode == "agent" then

local function response(id, ...)
	local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
	if not ok then
		-- if err == sockethelper.socket_error , that means socket closed.
		skynet.error(string.format("fd = %d, %s", id, err))
	end
end

local function readhtmlfile(path)

	local realpath
	if "" == path or "/" == path then
		realpath = "./examples/index.html"
	else
		realpath = "./examples/" .. path
	end

	local f = io.open(realpath,"r")
	if not f then return nil end

	html = f:read("a")
	f:close()

	return html
end

skynet.start(function()
	skynet.dispatch("lua", function (_,_,id)
		socket.start(id)
		-- limit request body size to 8192 (you can pass nil to unlimit)
		local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
		if code then
			if code ~= 200 then
				response(id, code)
			else

				-- 其它代码 拷贝 自 simpleweb.lua ，除了这里 :)
				local path, query = urllib.parse(url)
				local html = readhtmlfile(path)
				if html then
					local script,error = httpd.parse_htmlua(html)
					if script then
						-- 作为示例，将 code, header 传入到脚本中
						-- 你可以 传其它任何变量供 htmlua 脚本使用
						-- 脚本中这样访问： local var1,var2 = ...
						local ok,html_result = pcall(script,code, header)
						if ok then
							response(id, code, html_result)
						else
							response(id, code, "call script error:\n" .. html_result)
						end
					else
						response(id, code, "load script error:\n" .. error)
					end
				else
					response(id, code, "file '" .. path .. "' not found bb!")
				end

			end
		else
			if url == sockethelper.socket_error then
				skynet.error("socket closed")
			else
				skynet.error(url)
			end
		end
		socket.close(id)
	end)
end)

else

skynet.start(function()
	local agent = {}
	for i= 1, 20 do
		agent[i] = skynet.newservice(SERVICE_NAME, "agent")
	end
	local balance = 1
	local id = socket.listen("0.0.0.0", 8001)
	skynet.error("Listen web port 8001")
	socket.start(id , function(id, addr)
		skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
		skynet.send(agent[balance], "lua", id)
		balance = balance + 1
		if balance > #agent then
			balance = 1
		end
	end)
end)

end