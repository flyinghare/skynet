local internal = require "http.internal"

local table = table
local string = string
local type = type

local httpd = {}

local http_status_msg = {
	[100] = "Continue",
	[101] = "Switching Protocols",
	[200] = "OK",
	[201] = "Created",
	[202] = "Accepted",
	[203] = "Non-Authoritative Information",
	[204] = "No Content",
	[205] = "Reset Content",
	[206] = "Partial Content",
	[300] = "Multiple Choices",
	[301] = "Moved Permanently",
	[302] = "Found",
	[303] = "See Other",
	[304] = "Not Modified",
	[305] = "Use Proxy",
	[307] = "Temporary Redirect",
	[400] = "Bad Request",
	[401] = "Unauthorized",
	[402] = "Payment Required",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[406] = "Not Acceptable",
	[407] = "Proxy Authentication Required",
	[408] = "Request Time-out",
	[409] = "Conflict",
	[410] = "Gone",
	[411] = "Length Required",
	[412] = "Precondition Failed",
	[413] = "Request Entity Too Large",
	[414] = "Request-URI Too Large",
	[415] = "Unsupported Media Type",
	[416] = "Requested range not satisfiable",
	[417] = "Expectation Failed",
	[500] = "Internal Server Error",
	[501] = "Not Implemented",
	[502] = "Bad Gateway",
	[503] = "Service Unavailable",
	[504] = "Gateway Time-out",
	[505] = "HTTP Version not supported",
}

local function readall(readbytes, bodylimit)
	local tmpline = {}
	local body = internal.recvheader(readbytes, tmpline, "")
	if not body then
		return 413	-- Request Entity Too Large
	end
	local request = assert(tmpline[1])
	local method, url, httpver = request:match "^(%a+)%s+(.-)%s+HTTP/([%d%.]+)$"
	assert(method and url and httpver)
	httpver = assert(tonumber(httpver))
	if httpver < 1.0 or httpver > 1.1 then
		return 505	-- HTTP Version not supported
	end
	local header = internal.parseheader(tmpline,2,{})
	if not header then
		return 400	-- Bad request
	end
	local length = header["content-length"]
	if length then
		length = tonumber(length)
	end
	local mode = header["transfer-encoding"]
	if mode then
		if mode ~= "identity" and mode ~= "chunked" then
			return 501	-- Not Implemented
		end
	end

	if mode == "chunked" then
		body, header = internal.recvchunkedbody(readbytes, bodylimit, header, body)
		if not body then
			return 413
		end
	else
		-- identity mode
		if length then
			if bodylimit and length > bodylimit then
				return 413
			end
			if #body >= length then
				body = body:sub(1,length)
			else
				local padding = readbytes(length - #body)
				body = body .. padding
			end
		end
	end

	return 200, url, method, header, body
end

function httpd.read_request(...)
	local ok, code, url, method, header, body = pcall(readall, ...)
	if ok then
		return code, url, method, header, body
	else
		return nil, code
	end
end

local function writeall(writefunc, statuscode, bodyfunc, header)
	local statusline = string.format("HTTP/1.1 %03d %s\r\n", statuscode, http_status_msg[statuscode] or "")
	writefunc(statusline)
	if header then
		for k,v in pairs(header) do
			if type(v) == "table" then
				for _,v in ipairs(v) do
					writefunc(string.format("%s: %s\r\n", k,v))
				end
			else
				writefunc(string.format("%s: %s\r\n", k,v))
			end
		end
	end
	local t = type(bodyfunc)
	if t == "string" then
		writefunc(string.format("content-length: %d\r\n\r\n", #bodyfunc))
		writefunc(bodyfunc)
	elseif t == "function" then
		writefunc("transfer-encoding: chunked\r\n")
		while true do
			local s = bodyfunc()
			if s then
				if s ~= "" then
					writefunc(string.format("\r\n%x\r\n", #s))
					writefunc(s)
				end
			else
				writefunc("\r\n0\r\n\r\n")
				break
			end
		end
	else
		assert(t == "nil")
		writefunc("\r\n")
	end
end

function httpd.write_response(...)
	return pcall(writeall, ...)
end


--[[

 功能：处理 html 嵌入的 lua 脚本
 参数：
 	fileloader ：文件查找、加载函数，参数：file,curdir
 	rootdir ：web文件根路径，计算重定向路径时需要；必须以 "/" 结尾
 	file,url,header,body : 请求的相关信息
 说明：
	1、脚本中支持的内置函数/功能：
	 	echo(xxxx) ： 输出 html 内容。
		return url ：重定向页面
	2、脚本中支持的内置对象
	 	request ：可访问本次请求的相关数据

 返回值：正常，返回 200 和 页面内容；错误，返回错误号 和错误信息

--]]
function httpd.parse_htmlua(fileloader,file,url,header,body)

	-- 读取文件
	local htmlua = fileloader(file)
	if not htmlua then return 404,"file '" .. file .. "' not found!" end

	-- html 解析结果
	local html = {}

	-- 脚本中要用到的函数
	local function echo(s)
		table.insert(html,tostring(s))
	end

	-- 脚本序列
	local script = {}
	table.insert(script," local echo, redirect, request = ... ")

	-- 收集脚本
	local pos = 1
	while true do
		local openpos = htmlua:find("<?",pos,true)
		if openpos then

			-- 插入 html
			table.insert(script," echo([=[" .. htmlua:sub(pos,openpos-1) .. "]=]) ")

			-- 插入脚本
			local closepos = htmlua:find("?>",openpos + 1,true)
			if closepos then
				table.insert(script,htmlua:sub(openpos+2,closepos-1))
				pos = closepos+2
			else
				table.insert(script," echo(\"<br/>web script bracket '<?' not closed! <br/>\") ")

				break	-- 出错，退出
			end
		else
			-- 插入 html
			table.insert(script," echo([=[" .. htmlua:sub(pos,htmlua:len()) .. "]=]) ")

			break
		end
	end

	-- 返回载入的脚本
	local chunk,err = load(table.concat(script))
	if not chunk then
		return 500,"load script error:" .. err
	end

	local ok,refile = pcall(chunk,echo,redirect,{url=url,header=header,body=body})
	if not ok then
		return 500,"run script error:" .. ret
	end

	-- 重定向
	if refile then
		if refile[1] == "/" then
			ddd
			return httpd.parse_htmlua(fileloader,refile,url,header,body)
		else
			return httpd.parse_htmlua(rootdir, file:sub(1,string.find(file,"[^/\\]$")) .. refile,url,header,body)
		end
	end

	return 200,table.concat(html)
end

return httpd
