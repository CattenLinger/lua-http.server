local string = require'utils'.text
local table  = require'utils'.table
local os     = require'utils'.os
local log    = Logger

local dbgmod_apploader = IsDebugMode'apploader'
--[[ 
    It's a simple handler that prints request 
    details back to client
--]]
local DefaultEmptyDispatcher = function(_, _, request, response)
    local header_fields = {}
    local mxlen = 0
    for name, value in request.headers:each() do
        local nlen = #name
        if nlen > mxlen then mxlen = nlen end
        table.insert(header_fields, { nlen, name, value })
    end
    local header_lines = {}
    for _, item in ipairs(header_fields) do
        local len, name, value = table.unpack(item)
        table.insert(header_lines, string.nchar(mxlen - len)..name..': '..value)
    end
    response:status('200')
            :content_type('text/plain;charset=utf-8')
            :finish(table.concat(header_lines, '\n'))
end

local DefaultOnErrorHandler = function(err, _, _, _, response)
    if response.is_finished() then return end;
    response:status(500)
            :content_type('text/plain;charset=utf-8')
            :finish(err)
end

--[[
    Dispatcher 
--]]

local __proto = {
    on_reply = DefaultEmptyDispatcher;
    on_error = DefaultOnErrorHandler;
}

--- Dispatch procedure entry
local function dispatcher_entry(self, ...)
    local ok, res = pcall(self.on_reply, ...)
    if ok then return end

    log:error("[Dispatcher] %s", res)
    self.on_error(res, ...)
end

--[[
    Configuration loader
--]]

local config_helpers = {
    --[[
    TODO: allow plugins on response like adding custom `finish` method
    TODO: interceptors ?
    --]]
}

--- check if is a path in the current `package.path`
local function is_in_lua_path(path)
    for i in string.gmatch(package.path, '[^;]+') do
        if string.find(i, path, 0, true) then return true end
    end
    return false
end

local function dispatcher_normalizecfg(self, cfgval, env)
    do --[[ Check if on_reply is configured ]] 
        local on_reply = cfgval
        if type(cfgval) == 'function' then on_reply = cfgval end
        if not on_reply and type(env.on_reply) == 'function' then
            on_reply = env.on_reply
        end
        self.on_reply = on_reply

        if dbgmod_apploader and (self.on_reply == DefaultEmptyDispatcher) then 
            Logger:debug('[AppLoader] Default `on_reply()` is used')
        end
    end

    do --[[ Check if on_error is configured ]]
        if type(env.on_error) == 'function' then
            self.on_error = env.on_error
            Logger:debug('[AppLoader] No on_error handler is configured.')
        end

        if dbgmod_apploader and (self.on_error == DefaultOnErrorHandler) then 
            Logger:debug('[AppLoader] Default `on_error()` is used')
        end
    end
end


local function dispatcher_initcfg(self)
    local handler_dir = self.handler_dir or ''
    -- No handler configured, use default
    if handler_dir == '' then return dispatcher_normalizecfg(self, nil, {}) end;

    local resolver = os.path(self.handler_dir)
    local cfg_candidates, appcfg, metaenv = self.app_configurator({})
    -- Could not process configuration, use default
    if not cfg_candidates then return dispatcher_normalizecfg(self, nil, {}) end;
    
    local dir = tostring(resolver)
    -- Add the suit's root to lua search path
    if not is_in_lua_path(dir) then
        package.path = table.concat { dir..'/?.lua;'; dir..'/?/init.lua;'; package.path; }
        if dbgmod_apploader then log:trace('[AppLoader] Appended WebApp path to lua path: %s', dir) end
    end
    log:info('[AppLoader] Load codes from: %s', dir)

    ::load::
    local next_candidate = table.remove(cfg_candidates)
    if not next_candidate then critical('no configuration file found in target: '..dir) end
    local config_path = resolver:resolve(next_candidate)
    if dbgmod_apploader then log:trace('[AppLoader] app config candidate: '..config_path) end
    if not config_path then return end

    local cfgenv, cfg_idx_tbls = table.overlay { _ENV }
    self.config = cfgenv
    if dbgmod_apploader then log:info("[AppLoader] Load WebApp config from: " .. config_path) end
    table.insert(cfg_idx_tbls, config_helpers)

    -- Load config script
    local cfger, err = loadfile(config_path, 't', cfgenv)
    if not cfger then 
        if dbgmod_apploader then log:warn('[AppLoader] load configuration failed: ' .. tostring(err)) end
        goto load
    end
    
    -- Save some computed meta here
    appcfg.loader_ = { entry=config_path; root=dir; }

    -- Execute config script
    self.safemode(true)
    local ok, cfgval = pcall(cfger, dir, appcfg, metaenv)
    self.safemode(false)
    if not ok then critical('process configuration failed: '..tostring(cfgval)) end
    -- Remove dsl methods
    table.remove(cfg_idx_tbls)

    dispatcher_normalizecfg(self, cfgval, cfgenv)
end

local __mt={ __index=__proto, __call=dispatcher_entry }
local function dispatcher_constructor(options)
    local data = assert(options)
    setmetatable(data, __mt)
    dispatcher_initcfg(data)
    return data
end
return setmetatable({}, {
    __call = function(_, ...) return dispatcher_constructor(...) end
})