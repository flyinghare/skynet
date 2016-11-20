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

 htmlua 脚本中内置支持的函数：
	echo ：基本的输出函数

 用户 可在 生成 HTML 页面时传入 自定义的 对象或函数
 在 htmlua 脚本中用 类似如下的代码 接收：
 	local xx1,xx2,xx3 = ...

 返回值：一个 函数，执行次函数 即可生成 HTML 页面
--]]
function httpd.parse_htmlua(file)
	local f = io.open(file,"r")
	if not f then
		return nil
	end

	local text = f:read("a")
	if not text then
		f:close()
		return nil
	end
	f:close()

	-- 脚本序列
	local htmlua_script = {}
	table.insert(htmlua_script," local html_result={} local echo = function(str) table.insert(html_result,s) end ")

	-- 收集脚本
	local pos = 1
	while true do
		local openpos,openend = text:find("<?lua",pos,true)
		if openpos then

			-- 插入 html
			table.insert(htmlua_script," echo([[" .. text:sub(pos,openpos-1) .. "]]) ")

			-- 插入脚本
			local closepos,closeend = text:find("?>",openend,true)
			if closepos then
				table.insert(htmlua_script,text:sub(openend+1,closepos-1))
				pos = closeend + 1
			else
				table.insert(htmlua_script," echo(\"<br/>web script bracket '<?lua' not closed! <br/>\") ")

				break	-- 出错，退出
			end
		else
			-- 插入 html
			table.insert(htmlua_script," echo([[" .. text:sub(pos,text:len()) .. "]]) ")

			break
		end
	end

	-- 语句块 中的函数结束
	table.insert(htmlua_script," return table.concat(html_result) ")

	-- 返回载入的脚本
	return load(table.concat(htmlua_script))

end

return httpd
