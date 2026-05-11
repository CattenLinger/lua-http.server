local ce = require "cqueues.errno"
local log = require"utils".simple_log()

return function (server, stream, context)
	local real_path = context.real_path
	local headers, method = context.headers, context.method

    local res_headers = new_response_headers()

	local fd, err, errno = io.open(real_path, "rb")
	local code
	if not fd then
		if errno == ce.ENOENT then
			code = "404"
		elseif errno == ce.EACCES then
			code = "403"
		else
			code = "503"
		end
		res_headers:upsert(":status", code)
		res_headers:append("content-type", "text/html?charset=utf8")
		assert(stream:write_headers(res_headers, method == "HEAD"))
		if method == "HEAD" then return end
		
		pages'error.ltpl'({ path=context.path, code=code }, function(e) stream:write_chunk(e) end)
		stream:write_chunk('\n', true)
		return
	end
	
	res_headers:upsert(":status", "200")
	
    local mime_type = mime_mapping(context.real_path)

	log("Got a file: " .. mime_type)
	res_headers:append("content-type", mime_type)
	assert(stream:write_headers(res_headers, method == "HEAD"))
	if req_method ~= "HEAD" then
		assert(stream:write_body_from_file(fd))
	end
end