local search_jump_table = require'utils'.search_jump_table
local log = require'utils'.simple_log()

local unpack = table.unpack
local pack = table.pack

local M = { path="handlers/", mapping = {} }

local function new_env(init_content)
    local data = init_content or {}
    return setmetatable(data, { __index = _ENV })
end

local function M_load_handler(self, name, ...)
    local path = self.path..name..'.lua'
    local newenv = self.handler_env or new_env(loaderenv)
    local fn, e = loadfile(path, 'tb', newenv)
    if not fn then error(string.format('could not load handler code: %s', e)); end
    return fn(...), e
end

local InternalDefaultNotFoundHandler = { 
    function (server, stream)
        local res_headers = new_headers()
        res_headers:append(":status", "404")
        res_headers:append("server" , default_server)
        res_headers:append("date"   , http_util.imf_date())
        assert(stream:write_headers(res_headers, true))
    end;
    setmetatable({}, { __index = _ENV });
}

function M.dispatch(self, name, server, stream, ...)
    local name = name or ''
    if name == '' then name = 'default'; end

    local value do
        local cache = self.cache
        if cache then value = cache(name); end
        if value then goto end_load; end

        local success, fn, env = pcall(function() return M_load_handler(self, name); end)
        if not success then
            log("Could not load template '%s': %s", name, fn)
            value = InternalDefaultNotFoundHandler
        else
            value = { fn, env }
            if cache then cache:put(name, cached) end
        end
        ::end_load::
    end

    local pipeline, env = unpack(value)
    return pipeline(server, stream, ...)
end

function M.ingress(self, myserver, stream, context)
    local ingress = self.pipeline.ingress
    if ingress then return ingress(myserver, stream, context); end
    
    -- Default ingress
    local req_method = context.method
    if req_method ~= "GET" and req_method ~= "HEAD" then
        local res_headers = new_headers()
        res_headers:append(":status", "405")
        res_headers:append("server" , default_server)
        res_headers:append("date"   , http_util.imf_date())
		assert(stream:write_headers(res_headers, true))
		return
	end
    local file_type = lfs.attributes(context.real_path, "mode")
    context.file_type = file_type
    return file_type
end

local function M_init(self)
    if self.skip_config then return self; end

    self.handler_env = new_env(self.handler_env or {})
    local f_conf, err = loadfile(self.path..'.config.lua', 't', self.handler_env)
    
    if f_conf then 
        self.pipeline = f_conf() or {}
    else
        log('Ignore .config.lua file loading: %s', err)
    end

    return self
end

--[[
    no_cache      : boolean, disable cache.
    handler_env   : table, handle function _ENV.
    cache_options : table, see `cache.lua`.
]]--
return function(options)
    local data = options or {}
    if not data.no_cache then
        data.cache = require'cache'.new(data.cache_options or {})
    else
        log("Dynamic handler cache is disabled.")
    end

    return M_init(setmetatable(data, {
        __index = M;
        __call  = function(self, ...) self:dispatch(...); end
    }))
end