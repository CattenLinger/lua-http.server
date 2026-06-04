local table = require'utils'.table
local metatable = require'utils'.metatable

-- default values of each logger
local __defaults = { stream=io.stderr, level='TRACE', level_align='r', date_format='[%d/%b/%Y:%H:%M:%S %z]' }
local __proto_data = {}
local __proto = setmetatable({}, {
    __index = function(self, key) return __proto_data[key] or __defaults[key] end
})

if os.getenv('TERM'):lower():match('color$') then __proto.color = true end

-- function to get self meta data
local function meta(self) return rawget(self, '.') end
local function init_meta(self) rawset(self, '.', { _={} }) end

-- the writer
local function write(self, ...) self.stream:write(...) end
local function noop()  end
local function tag_date() return os.date("[%d/%b/%Y:%H:%M:%S %z]") end

local level_idx = {}
local level_map = {
    { 'ERROR' , {'\r\027[37;101;1m', '\027[0m', '', '\027[0m', '\027[31;1m'} };
    { 'WARN'  , {'\r\027[37;103;1m', '\027[0m', '', '\027[0m', '\027[33;1m'} };
    { 'INFO'  , {'\r\027[32;1m', '\027[0m', '', '\027[39m'} };
    { 'DEBUG' , {'\r\027[37m', '\027[0m',} };
    { 'TRACE' , {'\r\027[37;2m', '\027[0m'} };
}
for i, value in ipairs(level_map) do level_idx[value[1]] = i end
local function level_factory(self, idx, line_start, line_end, time_start, time_end, msg_start, msg_end)
    local t_lv = meta(self).level_formatter(level_map[idx][1])
    local t_d  = meta(self).date_formatter
    local ls, le, ts, te, ms, me = '', '', '', '', '', ''
    if self.use_color then
        le = line_end   or '\027[0m'; ls = line_start or '';
        ts = time_start or '';        te = time_end   or '';
        ms = msg_start  or '';        me = msg_end    or '';
    end
    local seg1 = ls..t_lv..ts
    local seg2 = te..' '..ms
    local seg3 = me..'\n'..le
    return function(_self, template, v, ...)
        if not v
        then return write(_self, seg1 ,t_d(), seg2, tostring(template),              seg3)
        else return write(_self, seg1, t_d(), seg2, string.format(template, v, ...), seg3)
        end
    end
end

function __proto.get_level_name(self)
    local level = meta(self).level
    if level <= 0 then return 'SILENCE' end
    return level_map[level][1]
end

local function rebuild_loggers(self, max_level)
    local _self = meta(self)
    max_level = max_level or _self.level
    local loggers = {}
    for i=0, #level_map do
        local c = level_map[i]
        if not c then goto continue end

        local name, params = table.unpack(c)
        if i <= max_level
        then loggers[name:lower()] = level_factory(self, i, table.unpack(params))
        else loggers[name:lower()] = noop
        end
        ::continue::
    end
    _self.loggers = loggers
end
function __proto.reconfigure(self) rebuild_loggers(self) end

local index_hook    = metatable.index_hook
local newindex_hook = metatable.newindex_hook
-- logger metatable
local __mt = { __class    = 'utils.logger' }

function __mt.__call(self, leading, ...)
    return self:info(leading, ...)
end

local getters, setters
__mt.__index, getters = index_hook.create {
    ['*'] = index_hook.computed(function(self, key)
        return meta(self)._[key] or __proto[key]
    end);
}
__mt.__newindex, setters = newindex_hook.create()

local loggers_indexer = function(self, key) return meta(self).loggers[key] end
for i = 1, #level_map do
    local name = string.lower(level_map[i][1])
    getters[name] = loggers_indexer
    setters[name] = newindex_hook.ignore()
end

-- Hook property 'level'
-- When level is changed, re-generate logging methods
getters.level = function(self, key)
    return meta(self)._[key] or __proto[key] or #level_map
end
setters.level = function (self, key, newval)
    local _self = meta(self)
    if rawequal(newval, _self[key] or __proto[key]) then return end
    _self._[key] = newval or __proto[key]

    local level = newval
    if type(level) ~= 'number' then level = (level_idx[level] or #level_map) end
    if level < 0 then level = 0 elseif level > #level_map then level = #level_map end
    _self.level = level
end

setters.level_align = function(self, key, newval)
    local _self = meta(self)
    if rawequal(newval, _self._[key] or __proto[key]) then return end
    local v = (newval or 'l'):lower():sub(1, 1):match('[lr]') or 'l'
    _self._[key] = v

    if v == 'l'
    then _self.level_formatter = function(s) return string.format('[%-6s]', s) end
    else _self.level_formatter = function(s) return string.format('[%6s]', s)  end
    end
end

setters.date_format = function(self, key, newval)
    local _self=meta(self)
    if rawequal(newval, _self._[key] or __proto[key]) then return end
    local v = newval or __proto[key]
    _self._[key] = v
    _self.date_formatter = function() return os.date(v) end
end

setters.use_color = function(self, key, newval)
    local _self=meta(self)
    if rawequal(newval, _self._[key] or __proto[key]) then return end
    if newval and self.color == false then return end
    _self._[key] = newval
end

--[[ Constructor ]]--
local simple_log = {}
function simple_log.is(target)
    if 'table' ~= type(target) then return false end
    local mt = getmetatable(target)
    return not (not mt or __mt ~= mt or __mt.__class ~= mt.__class)
end
local init_props = { 'use_color', 'level', 'date_format', 'level_align' }
function simple_log.create(options)
    if type(options) ~= 'table' then options = {} end
    local data = setmetatable(options or {}, __mt)
    init_meta(data)
    if not data.stream.write then error("log output target `stream` must be a stream") end
    for _, key in ipairs(init_props) do setters[key](data, key) end
    data:reconfigure()
    return data
end
function simple_log.set_defaults(self, options)
    __proto_data = options or {}
    return self
end
table.readonly(__mt)

--- Create a simple logger
---
---	@param target table logger options
---	@return table callable log context, when was called, behaves like `string.format`
return setmetatable({}, {
    __index    = simple_log;
    __call     = function(self, options) return self.create(options) end;
    __newindex = newindex_hook.ignore()
})