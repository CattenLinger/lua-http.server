local extext = require'utils'.text
local log = require'log'()

--[[ 
    It's a simple handler that prints request 
    details back to client
]]--
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
        table.insert(header_lines, extext.nchar(mxlen - len)..name..': '..value)
    end
    response:status('200')
            :content_type('text/plain;charset=utf-8')
            :finish(table.concat(header_lines, '\n'))
end

local DefaultOnErrorHandler = function(err, _, _, request, response)
    response:status(500)
            :content_type('text/plain;charset=utf-8')
            :finish(err)
end

--[[
    Dispatch procedure entry
--]]
local function dispatcher_entry(self, ...)
    local ok, res = pcall(self.on_reply, ...)
    -- TODO: error handler
    -- If no error handler is configured,
    -- use a default one with returning 500
    if ok then return end
    log:error("[Dispatcher] %s", res)
    self.on_error(res, ...)
end

--[[ Configuration loader ]]--
local extable = require'utils'.table

local config_helpers = {
    --[[
    TODO: allow plugins on response like adding custom `finish` method
    TODO: interceptors ?
    --]]
}

local function is_in_lua_path(path)
    for i in string.gmatch(package.path, '[^;]+') do
        if string.find(i, path, 0, true) then return true end
    end
    return false
end

local function dispatcher_checkcfg(self, options)
    local cfg_env, cfg_idx_tbls = extable.overlay { _G }
    self.config = cfg_env

    local config_path = CONFIG:resolve_handler('.config.lua')
    if not config_path then return end

    log:info("Load dispatcher config from: "..config_path)
    table.insert(cfg_idx_tbls, 1, config_helpers)

    -- Add the suit's root to lua search path
    if not is_in_lua_path(CONFIG.handler_dir) then
        package.path = table.concat {
            CONFIG.handler_dir..'/?.lua;';
            CONFIG.handler_dir..'/?/init.lua;';
            package.path;
        }
        log:debug('Appended handler path to lua path.')
    end

    -- Load config script
    local cfg,err = loadfile(config_path, 't', cfg_env)
    if not cfg then critical('load configuration failed: '..tostring(err)) end

    -- Execute config script
    local cfg_ok, resp = pcall(function() return cfg() end)
    if not cfg_ok then critical('process configuration failed: '..tostring(resp)) end
    -- Remove dsl methods
    table.remove(cfg_idx_tbls, 1)

    --[[ Check if on_reply is configured ]] do
        if type(resp) == 'function' then self.on_reply = resp end
        if not self.on_reply and type(cfg_env.on_reply) == 'function' then
            self.on_reply = cfg_env.on_reply
        end
        self.on_reply = self.on_reply or DefaultEmptyDispatcher
    end

    --[[ Check if on_error is configured ]] do
        if type(cfg_env.on_error) == 'function' then
            self.on_error = cfg_env.on_error
        end
        self.on_error = self.on_error or DefaultOnErrorHandler
    end
end

local __mt={ __call=dispatcher_entry }
local function dispatcher_constructor(options)
    local data = {}
    dispatcher_checkcfg(data, options)
    return setmetatable(data, __mt)
end
return setmetatable({

}, {
    __call = function(_, ...) return dispatcher_constructor(...) end
})