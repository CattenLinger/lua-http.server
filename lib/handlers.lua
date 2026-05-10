local search_jump_table = require'utils'.search_jump_table
local log = require'utils'.simple_log()

local M = { path="", mapping = {} }

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

local pack = table.pack
local unpack = table.unpack

function M.dispatch(self, name, ...)

    local value do 
        local cache = self.cache
        if cache then value = cache(name); end
        if value then goto end_load; end

        local fn, env = M_load_handler(self, name)
        value = { fn, env }
        if cache then cache:put(name, cached) end
        ::end_load::
    end

    return value[1](...)
end

local CfgEnv = new_env({ 
    routing=function(t) self.routing = t; end 
})

local function M_init(self)
    if self.skip_config then return self; end

    local env = setmetatable({}, { __index=CfgEnv })
    local f_conf, err = loadfile(self.path..'.config.lua', 't', env)
    if f_conf then 
        local dispatch_converter = f_conf();
        env = setmetatable(env, nil)
        self.config = env
    else
        self.config = {}
        log('Ignore .config.lua file loading: %s', err); 
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