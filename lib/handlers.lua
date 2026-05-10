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

function M.dispatch(self, name, ...)
    if name == '' then name = 'default'; end

    local cache = self.cache
    if not cache then goto loadraw; else
        local cached = cache(name)
        if cached then return cached[1](...); end
    end
    ::loadraw::

    local fn, env = M_load_handler(self, name)
    if cache then cache:put(name, { fn, env }) end
    return fn(...)
end

local function M_init(self)
    if self.skip_config then return self; end

    local env = new_env({ routing=function(t) self.routing = t; end })
    local f_conf, err = loadfile(self.path..'.config.lua', 't', env)
    if f_conf then f_conf(); else log('Ignore .config.lua file loading: %s', err); end

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