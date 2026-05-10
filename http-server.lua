#!/usr/bin/env lua
--[=[
This example serves a file/directory browser
It defaults to serving the current directory.

Usage: lua examples/serve_dir.lua [<port> [<dir>]]
]=]--
package.path = package.path .. ';./lib/?.lua;./lib/?/init.lua'
local log = require"utils".simple_log()
log('Lua Path: %s', package.path)

local CONFIG = require'config'(arg)

local http_server = require "http.server"
local http_util = require "http.util"
local http_version = require "http.version"

local lfs = require "lfs"
local lpeg = require "lpeg"
local uri_patts = require "lpeg_patterns.uri"


local uri_reference = uri_patts.uri_reference * lpeg.P(-1)

local function log_request(req_headers, stream)
	return log(
		'"%s %s HTTP/%g"  "%s" "%s"',
		req_headers:get":method" or "",
		req_headers:get":path" or "",
		stream.connection.version,
		req_headers:get"referer" or "-",
		req_headers:get"user-agent" or "-"
	)
end

--[[
	HTTP Handlers
]]--
local handlers = require'handlers' {
	path = 'handlers/';
	no_cache = true;
	handler_env = setmetatable({ 
		-- Template Engine
		pages = require"pages" {  path='pages/' };
		-- App Configuration
		CONFIG = CONFIG;
	}, { __index=_ENV })
};

--
-- Controller
--
local new_headers = require "http.headers".new
local dir = CONFIG.root_path
local default_server = string.format("%s/%s", http_version.name, http_version.version)
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
	local success, error = pcall(function()
		return handlers:dispatch(file_type, myserver, stream, context)
	end)
	if success then return; end
	log('Request process failed: %s', error)
end

local function onerror(myserver, context, op, err, errno)
	local msg = op .. " on " .. tostring(context) .. " failed"
	if err then msg = msg .. ": " .. tostring(err); end
	log(msg)
end

--
-- Server
--
local cqueues = require'cqueues'
local cq = cqueues.new()

--[[
	Cache cleaner
]]--
do
	local CacheObjectProviders = { 
		{ 'pages',    function() return pages.cache;    end };
		{ 'handlers', function() return handlers.cache; end };
	}

	cq:wrap(function()
		log("Cache evict job started.")
		::begin_loop::
		cqueues.sleep(1)
		local gc = false
		for _, pv in ipairs(CacheObjectProviders) do
			local name, provider = table.unpack(pv)
			local c = provider()
			if not c then goto continue; end
			local cache_evict_count = c:evict_cache()
			if cache_evict_count <= 0 then goto continue; end
			log("%d %s cache evicted.", cache_evict_count, name);
			gc = true
			::continue::
		end
		if gc then collectgarbage(); end
		goto begin_loop
	end)
end

local myserver = assert(http_server.listen {
	host = CONFIG.host[1];
	port = CONFIG.port;
	max_concurrent = 100;
	onstream = reply;
	onerror = onerror;
	cq = cq;
})

do -- Manually call :listen() so that we are bound before calling :localname()
	assert(myserver:listen())
	local bound_port = select(3, myserver:localname())
	log("Now listening on port %d", bound_port)
end

-- Start the main server loop
assert(myserver:loop())