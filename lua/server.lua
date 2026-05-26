--[[ Entry of the http server ]]--
local ServerCtx = {}
local _ENV__mt = { __index=ServerCtx }
setmetatable(_ENV, _ENV__mt)

--[[ Init essentials ]]--
local config = require'config'(arg)
local log = (require'log':set_defaults {
    use_color = config.log_color;
    level     = config.log_level or 'INFO'
}).create()
_ENV__mt.__newindex = function(self, key, value)
    rawset(ServerCtx, key, value)
    log:debug("Registered global %s '%s'",type(value),key)
end
CONFIG = config
log:info('Web root: %s', CONFIG.root_path)

-- install a critical() to improve the behavior of error()
require'utils'.install_critical {
    debug   = CONFIG.debug or false;
    printer = function(t, ...) log:error('!! FATAL !! '..t, ...) end
}

--[[ Coroutine ]]
EventQueue = require'cqueues'.new()

--[[ GC worker ]] do
    local clock = require'utils'.clock
    local cqueues = require'cqueues'
    local gc = false

    function _G.NotifyNextGC() gc = true end

    local lastgc = clock()
    local function check_force_gc(now)
        if (now - lastgc) <= 60 then return end;
        lastgc = now;
        gc = true;
        log:trace('Scheduled force GC to next check.')
    end

    log:info("GC trigger job stared, interval: 10s.")
    -- Check GC flag every 10 seconds
    EventQueue:wrap(function()
        log:info("GC trigger job stared, interval: 10s.")
        ::begin_loop::
        cqueues.sleep(10)
        check_force_gc(clock())
        if not gc then goto begin_loop end

        gc = false;
        local ret = collectgarbage();
        log:trace("GC triggered. (%d)", ret);
        goto begin_loop
    end)
end


--[[ Controller ]]
local Request  = require'request'
local Response = require'response'

--[[ Server reply method ]]
local server_onstream, server_onerror do
    local unpack = table.unpack

    local log_request = (function()
        -- Use null printer if is not using debug mode
        if not CONFIG.debug then return (function() end) end

        return function (req_headers, stream)
            return log:info(
                '"%s %s HTTP/%g"  "%s" "%s"',
                req_headers:get":method" or "",
                req_headers:get":path" or "",
                stream.connection.version,
                req_headers:get"referer" or "-",
                req_headers:get"user-agent" or "-"
            )
        end
    end)()
    
    local dispatcher = require'dispatcher' {
        path = CONFIG.handler_dir;
        no_cache = CONFIG.no_handler_cache;
        -- cache_options = CONFIG.handler_cache_options;
    }

    --[[
        The entry point of the server.
        It's called when a new stream is accepted.

        Error handling is not needed because non business logic errors will
        cause the stream to be closed, they are not recoverable.
    ]]--
    function server_onstream(server, stream) -- luacheck: ignore 212
        --[[ 
            Wrap request and response.
            It's a lazy table, so the properties will be computed
            when they are accessed.

            Also it acts as a request parsing step to validate the request.
        ]]--
        local request  = Request(server, stream);
        local response = Response(server, stream);

        -- Log the request basic info to stderr for debugging
        log_request(request.headers, stream)

        --[[ Select the appropriate handler and execute it ]]--
        dispatcher(server, stream, request, response)

        --[[
            Write contents to the stream.
        ]]--
        local finished, body_provider = unpack(response['.finish'] or {})
        if not finished then error('request end without finish') end

        local is_head_req = request.method == 'HEAD'
        stream:write_headers(response.headers, is_head_req)

        -- If it's a HEAD request, return immediately
        if is_head_req then return end

        --[[ Call the body generator ]]--
        body_provider()
    end

    function server_onerror(myserver, context, op, err, errno)
        local msg = string.format("%s on %s failed", op, tostring(context))
        if err then msg = string.format("%s: %s", msg, err); end
        log:error(msg)
    end
end

Server = assert(require'http.server'.listen {
    host = CONFIG.host[1];
    port = CONFIG.port;
    max_concurrent = 100;
    onstream = server_onstream;
    onerror = server_onerror;
    cq = EventQueue;
})

-- Manually call :listen() so that we are bound before calling :localname()
assert(Server:listen())
local bound_port = select(3, Server:localname())
log:info("Now listening on port %d", bound_port)

-- Start the main server loop
if not CONFIG.debug then
    local rs, e = pcall(function() return Server:loop(); end)
    if not rs then log:info("Server exited: %s", e); end
else
    log:info("Debug mode is enabled.")
    assert(Server:loop())
end