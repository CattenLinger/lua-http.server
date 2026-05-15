
--[[
    Entry of the http server
]]--
do
    local home = os.getenv("LUA_HTTP_SERVER_HOME")
    if not home or home == '' then 
        io.stderr:write('LUA_HTTP_SERVER_HOME missing.', '\n');
        os.exit(1);
    end
    package.path = ('%s;%s/lib/?.lua;%s/lib/?/init.lua'):format(package.path, home, home)
end

local log = require"utils".simple_log()

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
    Corotuine
]]--
local cqueues = require'cqueues'
local cq = cqueues.new()

--[[
	Cache cleaner
]]--
do
	local CacheObjectProviders = {}
    local Cache = require'cache'
    function _G.RegisterCacheCleaner(tb)
        local name, getter = table.unpack(tb)
        local c = getter()
        if not Cache.is(c) then error("Cache '"..name.."' is not a cache instance."); end
        table.insert(CacheObjectProviders, { name, getter });
    end

    local gc = false

	cq:wrap(function()
		log("Cache evict job started.")
		::begin_loop::
		cqueues.sleep(1)

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
		goto begin_loop
	end)

    cq:wrap(function()
        log("GC trigger job stared.")
        ::begin_loop::
        cqueues.sleep(10)
        if not gc then goto begin_loop; end

        gc = false; 
        collectgarbage(); 
        log("GC triggered."); 
        goto begin_loop
    end)
end

--[[
	HTTP Handlers
]]--
local handlers = require'handlers' {
	path        = CONFIG.handler_dir;
	no_cache    = CONFIG.no_handler_cache;
	skip_config = CONFIG.no_handler_config;

	handler_env = { 
		CONFIG = CONFIG; -- App Configuration
	}
};
RegisterCacheCleaner { 'handlers', function() return handlers.cache; end };


--[[
    Controller
]]--

local new_headers = require "http.headers".new
local dir = CONFIG.root_path
local default_server = string.format("%s/%s", http_version.name, http_version.version)

local function reply(myserver, stream) -- luacheck: ignore 212

	-- Read in headers
	local req_headers = assert(stream:get_headers())
	local req_method  = req_headers:get":method"

	-- Log request to stderr
	log_request(req_headers, stream)

	local path = req_headers:get(":path")
	local uri_t = assert(uri_reference:match(path), "invalid path")
	path = http_util.resolve_relative_path("/", uri_t.path)
	local real_path = dir .. http_util.decodeURIComponent(path)

	local context = {
        headers=req_headers; method=req_method;
        path=path;           real_path=real_path;
    }
	local success, error = pcall(function()
        local handler_name = handlers:ingress(myserver, stream, context)

        -- Handlers use an overlay context
        context = setmetatable({}, { __index = context })
		return handlers:dispatch(handler_name or 'default', myserver, stream, context)
	end)
	if success then return; end

	log('Request process failed: %s', error.message or tostring(error))
    if type(error) == 'table' then
        error(error)
    else 
        error(setmetatable({ message = tostring(error) }, { __index=context })) 
    end
end

local function onerror(myserver, context, op, err, errno)
	local msg = op .. " on " .. tostring(context) .. " failed"
	if err then msg = msg .. ": " .. tostring(err); end
	log(msg)
end

--
-- Server
--


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
if not CONFIG.debug then
    local rs, e = pcall(function() return myserver:loop(); end)
    if e then log("Server exited: %s", e); end
else
    log("Debug mode is enabled.")
    assert(myserver:loop())
end