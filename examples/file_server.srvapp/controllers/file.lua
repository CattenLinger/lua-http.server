local log = require"log"()
local ce  = require "cqueues.errno"

local mime = (function()
	local fd, err = io.open(CONFIG:resolve_handler('mime.type.txt'))
	if not fd then critical('Failed to load MIME: '..err) end
	local r = require'lib.mime'(fd)
	return r
end)()
local render_error = pages'error.ltpl'

local function on_notfound(request, response)
	response:finish(render_error {
		title = 'Not found';
		page_title = 'Not Found: ' .. request.path;
		description = 'The content you request is not exists.'
	})
end

local function on_denied(_, response)
	response:finish(render_error {
		title = 'Access denied';
		page_title = 'Access denied';
		description = ''
	})
end

local function on_error(_, response)
	response:finish(render_error {
		title = 'Service unavailable';
		page_title = 'unknown error';
		description = ''
	})
end

return function (request, response)
	local real_path, method = request.real_path, request.method
	if method ~= 'GET' and method ~= 'HEAD' then
		return response:status(405):finish()
	end

	local fd, err, errno = io.open(real_path, "rb")
	local code
	if not fd then
		local next
		if errno == ce.ENOENT then
			code = "404"
			next = on_notfound
		elseif errno == ce.EACCES then
			code = "403"
			next = on_denied
		else
			code = "503"
			next = on_error
		end
		log:info("[Handler: file] Access to %s failed: %s", real_path, err)
		response:status(code):content_type("text/html?charset=utf8")
		if method == "HEAD" then return end
		return next()
	end

	response:status("200")
	
    local mime_type = mime:content_type_of(request.path:lower())

	log:info("Got file %s , type: %s", real_path, mime_type)
	response:content_type(mime_type)
	if method ~= "HEAD" then response:finish(fd) end
end