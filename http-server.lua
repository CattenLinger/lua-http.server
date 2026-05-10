#!/usr/bin/env lua
--[=[
This example serves a file/directory browser
It defaults to serving the current directory.

Usage: lua examples/serve_dir.lua [<port> [<dir>]]
]=]--
package.path = package.path .. ';./lib/?.lua;./lib/?/init.lua'
local CONFIG = require'config'(arg)

local http_server = require "http.server"
local http_util = require "http.util"
local http_version = require "http.version"
local ce = require "cqueues.errno"
local lfs = require "lfs"
local lpeg = require "lpeg"
local uri_patts = require "lpeg_patterns.uri"
local mime_mapping = require'mime'

local uri_reference = uri_patts.uri_reference * lpeg.P(-1)

local default_server = string.format("%s/%s", http_version.name, http_version.version)

local human = require"utils".human
local log = require"utils".simple_log()
local function log_request(req_headers, stream)
	return log(
		'[%s] "%s %s HTTP/%g"  "%s" "%s"',
		os.date("%d/%b/%Y:%H:%M:%S %z"),
		req_headers:get":method" or "",
		req_headers:get":path" or "",
		stream.connection.version,
		req_headers:get"referer" or "-",
		req_headers:get"user-agent" or "-"
	)
end

local pages = require"pages" { 
	path='pages/'
}

local template = require"template"
local json = require"json"

local handlers = {
	['directory'] = function(server, stream, context)
		local headers, method = context.headers, context.method
		local real_path, path = context.real_path, context.path

		-- directory listing
		path = path:gsub("/+$", "") .. "/"
		headers:upsert(":status", "200")
		headers:append("content-type", "text/html; charset=utf-8")
		assert(stream:write_headers(headers, method == "HEAD"))
		
		if req_method == 'HEAD' then return; end

		local files = {}
		local model = { path=path, files=files }
		
		-- lfs doesn't provide a way to get an errno for attempting to open a directory
		-- See https://github.com/keplerproject/luafilesystem/issues/87
		for filename in lfs.dir(real_path) do
			-- Exclude parent directory entry listing from top level
			if (filename == ".." and path == "/") then goto continue; end

			local stats = lfs.attributes(real_path .. "/" .. filename)
			if stats.mode == "directory" then
				filename = filename .. "/"
			end

			table.insert(files, {
				css_cls  = stats.mode:gsub("%s", "-");
				href     = http_util.encodeURI(path .. filename);
				filename = filename;
				size     = stats.size;
				size_h   = human(stats.size);
				time     = os.date("!%Y-%m-%d %X", stats.modification)
			})
			::continue::
		end

		pages'index.ltpl'(model, function(s) assert(stream:write_chunk(s)); end)
		stream:write_chunk('\n', true)
	end;

	['file'] = function(server, stream, context)
		local real_path = context.real_path
		local headers, method = context.headers, context.method

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
			headers:upsert(":status", code)
			headers:append("content-type", "text/html?charset=utf8")
			assert(stream:write_headers(headers, method == "HEAD"))
			if method == "HEAD" then return end
			
			pages'error.ltpl'({ path=context.path, code=code }, function(e) stream:write_chunk(e) end)
			stream:write_chunk('\n', true)
			return
		end
		
		headers:upsert(":status", "200")
		local mime_type = mime_mapping(context.real_path)
		log("Got a file: " .. mime_type)
		headers:append("content-type", mime_type)
		assert(stream:write_headers(headers, method == "HEAD"))
		if req_method ~= "HEAD" then
			assert(stream:write_body_from_file(fd))
		end
	end;

	[''] = function(server, stream, context)
		local headers = context.headers
		headers:upsert(":status", "404")
		assert(stream:write_headers(headers, false))
		pages'error.ltpl'({ path=context.path, code="404" }, function(e) stream:write_chunk(e) end)
		stream:write_chunk('\n', true)
	end
}

--
-- Controller
--
local new_headers = require "http.headers".new
local dir = CONFIG.root_path
local function reply(myserver, stream) -- luacheck: ignore 212
	-- Read in headers
	local req_headers = assert(stream:get_headers())
	local req_method  = req_headers:get":method"

	-- Log request to stderr
	log_request(req_headers, stream)

	-- Build response headers
	local res_headers = new_headers()
	res_headers:append(":status", nil)
	res_headers:append("server", default_server)
	res_headers:append("date", http_util.imf_date())

	if req_method ~= "GET" and req_method ~= "HEAD" then
		res_headers:upsert(":status", "405")
		assert(stream:write_headers(res_headers, true))
		return
	end

	local path = req_headers:get(":path")
	local uri_t = assert(uri_reference:match(path), "invalid path")
	path = http_util.resolve_relative_path("/", uri_t.path)
	local real_path = dir .. path

	local context = { 
		headers=req_headers; method=req_method;
		path=path; real_path=real_path;
	}
	local file_type = lfs.attributes(real_path, "mode")
	local handler = handlers[file_type or '']
	if handler then 
		handler(myserver, stream, context)
		return
	end

	log("Attempted to access unsupported type: ", file_type)
	res_headers:upsert(":status", "403")
	assert(stream:write_headers(res_headers, true))
	
end

--
-- Server
--
local cqueues = require'cqueues'
local cq = cqueues.new()
local myserver = assert(http_server.listen {
	host = CONFIG.host[1];
	port = CONFIG.port;
	max_concurrent = 100;
	onstream = reply;
	onerror = function(myserver, context, op, err, errno) -- luacheck: ignore 212
		local msg = op .. " on " .. tostring(context) .. " failed"
		if err then
			msg = msg .. ": " .. tostring(err)
		end
		assert(io.stderr:write(msg, "\n"))
	end;
	cq = cq;
})

-- Manually call :listen() so that we are bound before calling :localname()
assert(myserver:listen())
do
	local bound_port = select(3, myserver:localname())
	assert(io.stderr:write(string.format("Now listening on port %d\n", bound_port)))
end

-- Start the main server loop
myserver:loop()
