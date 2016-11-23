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

	local html = f:read("a")
	f:close()

	return html
end

local function parse_request(url, method, header, body)
	local path, query = urllib.parse(url)
	local file_content = readhtmlfile(path)
	if file_content then

		local request = {url=url,method=method,header=header,body=body }
		if "POST" == method then
			request.post = urllib.parse_query(body)
		elseif "GET" == method then
			request.get = urllib.parse_query(query)
		end

		return httpd.parse_htmlua(file_content,{},request,function(reurl)
			return parse_request(reurl, method, header, body)
		end)
	else
		return 404, "file '" .. path .. "' not found!"
	end
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
				response(id, parse_request(url, method, header, body))
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