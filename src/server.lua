--[[ Init essentials ]]--
local table  = require'utils'.table
local config = require'config'(arg)

IsDebugMode = (function() --[[ Debug Mode Getter ]]
    local opts = config.debug
    if not opts then return function() return false end end

    opts = table.to_set(opts)
    if opts.all then return function() return true end end

    return function(s)
        if not s then return true end
        return opts[s] or false
    end
end)()
local is_debug_mode_ = IsDebugMode()

local log = (require'log':set_defaults {
    use_color = config.log_color;
    level     = config.log_level or 'INFO'
}).create()
Logger = log;


--[[ Entry of the http server ]]--
local ServerENV, ServerENV_locked = {}, false
local global_indexer_ = function(self, key) return ServerENV[key] end
local Global, Global_mt_ = _ENV, { __index=global_indexer_ }
local rawset, rawget = rawset, rawget
local setmetatable, getmetatable = setmetatable, getmetatable
setmetatable(Global, Global_mt_)
-- move all values out of the default ENV
for key, value in pairs(Global) do
    rawset(ServerENV, key, value)
    rawset(Global, key, null)
end

do --[[ Servet Global ENV Protect]]
    local dbgmod_server_env = IsDebugMode'env'
    local warn_str = "[Server ENV] Rejected global %s '%s': server global is protected."
    if dbgmod_server_env then warn_str = warn_str .. ' %s' end

    local on_warn if not dbgmod_server_env then 
        on_warn = function(key, value) log:warn(warn_str, type(value), key) end
    else
        local dbg = require'debug'
        on_warn = function(key, value) log:warn(warn_str, type(value), key, dbg.traceback()) end
    end

    Global_mt_.__newindex = function(_, key, value)
        if ServerENV_locked then return on_warn(key, value) end
        rawset(ServerENV, key, value)
        log:debug("[Server ENV] Registered global %s '%s'", type(value), key)
    end
end

do --[[ Trapped getmetatable and setmetatable ]]
    local dbgmod_getsetmetatble = IsDebugMode'env'
    local warn_str = '[Server ENV] Attempted to get/set metatable on protected GLOBAL. '
    if dbgmod_getsetmetatble then warn_str = warn_str .. ' %s' end
    local on_warn if not dbgmod_getsetmetatble then
        on_warn = function() log:warn(warn_str) end
    else
        local dbg = require'debug'
        on_warn = function() log:warn(warn_str, dbg.traceback()) end
    end

    ServerENV.setmetatable = function(t, ...)
        if not rawequal(t, Global) then return setmetatable(t, ...) end;
        on_warn()
    end
    ServerENV.getmetatable = function(t, ...)
        if not rawequal(t, Global) then return getmetatable(t, ...) end;
        on_warn()
    end
end



-- install a critical() to improve the behavior of error()
require'utils'.install_critical {
    debug   = is_debug_mode_;
    printer = function(t, ...) log:error('!! FATAL !! '..t, ...) end
}

--[[ Coroutine ]]
EventQueue = require'cqueues'.new()

--[[ GC worker ]] do
    local clock = require'utils'.clock
    local cqueues = require'cqueues'
    local gc = false
    local dbgmod_gc = IsDebugMode'gc'

    function _G.NotifyNextGC() gc = true end

    local lastgc = clock()
    local function check_force_gc(now)
        if (now - lastgc) <= 60 then return end;
        lastgc = now;
        gc = true;
        if dbgmod_gc then log:trace('[GC] Scheduled force GC to next check.') end
    end

    -- Check GC flag every 10 seconds
    EventQueue:wrap(function()
        if dbgmod_gc then log:info("[GC] GC trigger job stared, interval: 10s.") end
        ::begin_loop::
        cqueues.sleep(10)
        check_force_gc(clock())
        if not gc then goto begin_loop end

        gc = false;
        local ret = collectgarbage();
        if dbgmod_gc then log:trace("[GC] GC triggered. (%d)", ret) end
        goto begin_loop
    end)
end


--[[ Controller ]]
local Request  = require'request'
local Response = require'response'

--[[ Server reply method ]]
local server_onstream, server_onerror do
    local unpack = table.unpack
    local dbgmod_request = IsDebugMode'request'

    local log_request = (function()
        -- Use null printer if is not using debug mode
        if not dbgmod_request then return (function() end) end

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
    
    --- Create app loader
    local dispatcher = require'dispatcher' {
        handler_dir      = config.handler_dir;
        app_configurator = config.appcfger_ or function() end;
        safemode         = function(b) ServerENV_locked = b end;
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
        if err   then msg = string.format("%s: %s", msg, err) end
        if errno then msg = string.format("%s (%s)", msg, tostring(errno)) end
        log:error(msg)
    end
end

Server = assert(require'http.server'.listen {
    host = config.host[1];
    port = config.port[1];
    max_concurrent = 100;
    onstream = server_onstream;
    onerror = server_onerror;
    cq = EventQueue;
})

-- Manually call :listen() so that we are bound before calling :localname()
assert(Server:listen())
local bound_port = select(3, Server:localname())
log:info("[Server] Now listening on port %d", bound_port)

-- Start the main server loop
ServerENV_locked = true
if not is_debug_mode_ then
    local rs, e = pcall(Server.loop, Server)
    if not rs then log:info("[Server] Server exited: %s", e); end
else
    local debug_flags = table.keys(table.to_set(config.debug))
    if #debug_flags < 1 then log:info('[Server] Debug mode is enabled.') else
        log:info("[Server] Debug mode is enabled: %s", table.concat(debug_flags, ','))
    end
    assert(Server:loop())
end