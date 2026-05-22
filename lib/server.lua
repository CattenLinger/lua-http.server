--[[ Entry of the http server ]]--
do
    local home = os.getenv("LUA_HTTP_SERVER_HOME")
    if not home or home == '' then 
        io.stderr:write('LUA_HTTP_SERVER_HOME missing.', '\n');
        os.exit(1);
    end
    package.path = table.concat {
        home..'/lib/?.lua;'; home..'/lib/?/init.lua;';
        package.path;
    }
end

--[[ Init essentials ]]--

CONFIG = require'config'(arg)
local log = (require'log':set_defaults {
    use_color=CONFIG.log_color;
    level = CONFIG.log_level or 'INFO'
})()
log:debug("Registered Gloabl ENV: CONFIG")
-- install a critical() to improve the behavior of error()
require'utils'.install_critical {
    debug=CONFIG.debug or false;
    printer=function(t, ...) log:error('!! FATAL !! '..t, ...) end
}

--[[ Coroutine ]]
EventQueue = require'cqueues'.new()
log:debug("Registered Gloabl ENV: EventQueue")

--[[ Cache cleaner ]] do
    local cqueues = require'cqueues'
    local gc = false
    function _G.NotifyNextGC() gc = true end
    log:debug("Registered Gloabl ENV: NotifyNextGC")

    EventQueue:wrap(function()
        log:info("GC trigger job stared, interval: 10s.")
        ::begin_loop::
        cqueues.sleep(10)
        if not gc then goto begin_loop; end

        gc = false;
        local r = collectgarbage();
        log:trace("GC triggered. (%d)", r);
        goto begin_loop
    end)
end


--[[ Controller ]]
local extable = require'utils'.table

--[[ Server request wrapper ]]
local Request do
    local http_util = require "http.util"
    local lpeg      = require "lpeg"
    local uri_patts = require "lpeg_patterns.uri"
    local uri_ref   = uri_patts.uri_reference * lpeg.P(-1)

    local dir = CONFIG.root_path

    local function get_headers(self)
        return assert(self.stream:get_headers())
    end
    
    local function get_method(self)
        return assert(self.headers:get':method')
    end

    local function get_path(self)
        path = assert(self.headers:get':path')
        local uri_t = assert(uri_ref:match(path), "invalid path")
        return http_util.resolve_relative_path("/", uri_t.path)
    end

    local function get_real_path(self)
        return dir .. http_util.decodeURIComponent(self.path)
    end

    function Request(server, stream)
        return extable.lazy {
            stream    = stream;
            headers   = get_headers;
            method    = get_method;
            path      = get_path;
            real_path = get_real_path;
        };
    end
end

--[[ Server response wrapper ]]
local Response do
    local http_util      = require "http.util"
    local new_headers    = require "http.headers".new
    local http_version   = require "http.version"
    local default_server = string.format("%s/%s", http_version.name, http_version.version)

    local function assert_context_not_finished(self)
        if (self['.finish'] or {})[1] 
        then error('try to act on a finished context') 
        end
    end
    
    local function create_new_header(self)
        assert_context_not_finished(self)

        local headers = new_headers()
        headers:append("server", default_server)
        headers:append("date", http_util.imf_date())
        return headers
    end

    local function set_content_type(self, ct)
        assert_context_not_finished(self)
        self.headers:append('content-type', ct)
        return self
    end

    local function set_status(self, st)
        assert_context_not_finished(self)
        if type(st) ~= 'string' then st = tostring(st) end
        self.headers:append(":status", st)
        return self
    end

    local function finish(self, value, ...)
        assert_context_not_finished(self)

        local stream = self.stream
        local args = table.pack(...)

        -- If has no value
        if value == nil and #args <= 0 then
            self['.finish'] = { true; function()
                stream:write_chunk('', true)
            end }
        end

        local value_t = type(value)
        if value_t == 'userdata' then
            self['.finish'] = { true; function()
                stream:write_body_from_file(value)
            end }
            return
        end

        -- If it's a value
        if value_t ~= 'function' then
            self['.finish'] = { true; function()
                stream:write_chunk(tostring(value), false)
                for i, k in ipairs(args) do
                    stream:write_chunk(tostring(k), false)
                end
                stream:write_chunk('', true)
            end }
            return
        end

        local writer = function(chunk)
            return stream:write_chunk(chunk, false)
        end
        self['.finish'] = { true; function()
            value(writer, table.unpack(args))
            stream:write_chunk('', true)
        end }
    end

    function Response(server, stream)
        return extable.lazy {
            -- Properties
            stream       = stream;
            headers      = create_new_header;
            -- Methods
            content_type = function() return set_content_type end;
            status       = function() return set_status end;
            finish       = function() return finish end;
        }
    end
end

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

    local mt_error = { __tostring = function(self) return self[1] or 'nil'; end }

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
log:debug("Registered Gloabl ENV: Server")

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