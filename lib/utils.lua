local utils = {}

--- Get the current time in seconds.
--- @return number the result of os.clock() * 100 (seconds)
function utils.clock() return os.clock() * 100 end

--- Install a function `critical` that fail when is called.
--- If options.debug is true, it use the error() method, otherwise
--- it will print the message and exit the program immediately.
---
--- Accepted options:
--- - debug: boolean
---
--- @param options table
--- @return void
function utils.install_critical(options)
    options = options or {}
    local log = options.printer or function(msg) print(msg) end

    if options.debug then
        _G.critical = function(msg) error(msg, 2) end
        return
    end
    _G.critical = function(msg) log(msg); os.exit(1); end
end

--[[ Parse command line arg to a list of groups.

	Example:
	args input: -h localhost -p 8000 -d . -dH handlers/
	output:
	{
		'-h', {'localhost', '127.0.0.1'};
		'-p', {'8000'};
		'-d', {'.'};
		'-dH', {'handlers/'};
	}

	@param args - the command line args
	@return the input table of groups
--]]
function utils.arg_parse(args)
    local arg_list, props = {}, {}
    while true do
        local v = table.remove(args)
        if v == nil then break; end

        if string.sub(v, 1, 1) ~= '-' then
            table.insert(props, v)
        else
            table.insert(arg_list, { v, props })
            props = {}
        end
    end

    if #props > 0 then table.insert(arg_list, { '', props }); end
    return arg_list
end

--[[ Os utility (does not supporting windows) ]] do
    local exos = {}
    utils.os = exos

    --[[
        Resolve a path to absolute real path
    ]]--
    function exos.realpath(path)
        local fd = io.popen("realpath '"..path.."'")
        if not fd then error('could not execute shell command for realpath') end
        local path = fd:read('l')
        fd:close()
        return path
    end

    --[[
        Split a path to list of segments

        It does a very naive seperation with '/', so
        directory will be ends with '/' .
    ]]--
    function exos.pathsegs(path)
        if not path then  return path end
        if #path < 1 then return nil  end
        local segs = {}
        local nidx = 0
        while true do
            local cidx = string.find(path, '/', nidx, true)
            if not cidx then break end
            table.insert(segs, string.sub(path, nidx, cidx))
            nidx = cidx + 1
        end
        if nidx <= #path then table.insert(segs, string.sub(path, nidx)) end
        return segs
    end

    --[[
        resolve a relative path.
    ]]--
    function exos.resolve(path)
        local segs = exos.pathsegs(path)
        if #segs == 0 then return nil end;

        local npath = {}
        for idx, seg in ipairs(segs) do
            -- filter out any part with only '.' and '/'
            local rel = string.match(seg, '^[%./]+$')
            if not rel then goto insert end;
            if rel == '/' then
                -- ignore any '/' between segments
                if idx > 1 then goto continue end
                goto insert
            end
            if rel == '.' or rel == './'  then
                if idx > 1 then goto continue end
                seg = './'; -- normalize '.'
                goto insert;
            end
            if rel == '..' or rel == '../' then
                table.remove(npath)
                if #npath > 0 then goto continue end
                seg = './'; -- use './' if has no parent (chroot-ed)
                goto insert;
            end
            -- things like '...../' is illegal
            do return nil end
            ::insert::
            table.insert(npath, seg)
            ::continue::
        end
        -- empty path just same as nil
        if #npath == 0 then return nil end
        return table.concat(npath)
    end
end

--[[ Text utility functions ]] do
    local extext = {}
    utils.text = extext
    --[[
        Repeat a text sequence in num times.
        Usually is for spacing when formatting.

        @param num repeat count
        @param c optional text, default is ' '
        @return a string
    ]]
    function extext.nchar(num, c)
        c = c or ' '
        local str = ''
        for i=1, num do str = str..tostring(c) end
        return str
    end
end

--- Search a jump table uses string as key with non
--- string value.
---
--- @param jtb      table the jump table to search
--- @param key      string the key to search
--- @param max_jump number the maximum number of jumps allowed
---
--- @return any, string the value and the final key if found, otherwise nil
function utils.search_jump_table(jtb, key, max_jump)
    max_jump = max_jump or 3
    local cnt, k = max_jump, key
    ::search::
    local v = jtb[k]
    if type(v) ~= 'string' then return v, k; end

    if cnt <= 0 then error("jump table max redirect reached: "..tostring(max_jump)); end
    k = v
    cnt = cnt - 1
    goto search
end

--[[ Table utility ]] do
    local extable = {}
    utils.table = extable

    local extable_mt = { __index = table; }
    extable_mt.__call = function(self, tbl)
        tbl = tbl or {}
        if self.is(tbl) then return tbl end;
        return setmetatable(tbl, extable);
    end
    setmetatable(extable, extable_mt)

    function extable.is(tb)
        local mt = getmetatable(tb)
        if not mt then return false; end
        local ex = mt.__extable
        if ex then return true end
        return false
    end

    local function extable_idx(__extable, self, key)
        local searcher = __extable.searcher
        local idx = searcher.indecies
        local v for k, v in ipair(idx) do
            if type(idx) == 'table'
            then v = idx[k]
            else v = idx(self, k)
            end
            if v ~= nil then break end;
        end
        return v
    end

    --[[ Overlay table ]]--
    local function overlay_search(backups, _, key)
        for _, backup in ipairs(backups) do
            v = backup[key]
            if v ~= nil then return v end
        end
        -- return nil
    end
    --- Create a table that search value from backups
    --- if use only one param, target will be backups and returns a
    --- newly created table
    ---
    --- @param target table set nil to create a new empty table
    --- @param backups table list of tables as it's value backup
    --- @return table target table
    function extable.overlay(target, backups)
        if not backups then backups = target; target = {}; end
        local __mt = {}
        __mt.__index = function(...) return overlay_search(backups, ...) end
        return setmetatable(target, __mt), backups
    end

    --[[ Lazy table ]]--
    local function lazytable_get(mt, t, k)
        local get = mt.getters[k]
        if 'function' == type(get) then return get(t, k) end
        return get;
    end
    local function lazytable_cached(mt, t, k)
        local v = rawget(t, k)
        if v ~= nil then return v end
        v = lazytable_get(mt, t, k)
        rawset(t, k, v)
        return v
    end
    function extable.computed(getters, options)
        options = options or {}
        local mt = { getters=getters }
        local ot = options[1] or {}

        if options.cached == true
        then mt.__index = function(...) return lazytable_cached(mt, ...); end
        else mt.__index = function(...) return lazytable_get(mt, ...);    end
        end

        return setmetatable(ot, mt)
    end
    function extable.lazy(getters)
        return extable.computed(getters, { cached=true })
    end

    --[[ return keys of a table ]]--
    function extable.keys(tb)
        local keys = {}
        for k,_ in pairs(tb) do table.insert(keys, k) end
        return keys
    end

    --[[
        Copy a table. If target is not gave,
        returns a new table
    ]]--
    function extable.copy(from, to)
        local n = to or {}
        for k, v in pairs(from) do n[k] = v end
        return n
    end

    --[[ Readonly Table ]]--
    local readonly_mt = { __newindex=function()
        error('attempted to modify a readonly table', 2)
    end }
    --- Make target table readonly
    --- @param target table
    --- @return table
    function extable.readonly(target)
        return setmetatable(target or {}, readonly_mt)
    end

    function extable.print(tb, p)
        local print = p or print
        for k, v in pairs(tb) do print(k, v) end
    end
end

--[[ Meta Table Utils ]] do
    local exmeta = {}
    utils.metatable = exmeta

    local index_hook = {}
    exmeta.index_hook = index_hook

    --- Create a index hook method.
    --- A hook handler value must be a function.
    --- A special key '*' is used to register a default handler
    --- if no any handler match, can be used as the fallback __index
    ---
    --- @param hooks table a key value table with key handlers
    --- @return function, table first is the __index function, second is all the hooks
    function index_hook.create(hooks)
        hooks = hooks or {}
        return function(self, key)
            local h = hooks[key] or hooks['*']
            if not h then return rawget(self, h) end
            return h(self, key)
        end, hooks
    end

    --- Create a default value hook
    --- @param value any
    --- @return function
    function index_hook.default(value)
        if type(value) == 'function' then return value end
        return function() return value end
    end
    --- Create a lazy value hook
    --- @param value function|any provider or a plain value
    --- @param raw string|boolean if is 'raw' or true, bypass meta methods
    --- @return function
    function index_hook.lazy(value, raw)
        if type(value) ~= 'function'
        then value = function() return value end
        end

        if raw == 'raw' or raw == true
        then return function(self, key) rawset(self, key, value()) end
        else return function(self, key) self[key] = value()        end
        end
    end
    function index_hook.computed(value)
        if type(value) == 'function'
        then return value
        else return function() return value end
        end
    end

    local newindex_hook = {}
    exmeta.newindex_hook = newindex_hook
    --- Create a newindex hook method
    --- a hook handler value must be a function
    ---
    --- @param hooks table a key value table with key handlers
    --- @return function, table first is the __newindex function, second is all the hooks
    function newindex_hook.create(hooks)
        hooks = hooks or {}
        return function(self, key, value)
            local h = hooks[key]
            if not h then return rawset(sef, key, value) end
            return h(self, key, value)
        end, hooks
    end

    local newindex_hook_noop = function()  end
    --- Returns a method do nothing when set a value
    function newindex_hook.ignore()
        return newindex_hook_noop
    end

    local newindex_hook_reject = function(_, key) error('attempted to modify a readonly value: '..key) end
    --- Returns a method throw error when set a value
    function newindex_hook.reject()
        return newindex_hook_reject
    end
end

--- Convert byte to human friendly format
--- @param n number the byte to convert
--- @return string the human friendly format
utils.human = (function()
    local suffixes = {
        [0] = "";
        [1] = "K";
        [2] = "M";
        [3] = "G";
        [4] = "T";
        [5] = "P";
    }

    local log = math.log
    if _VERSION:match("%d+%.?%d*") < "5.1" then
        log = require "compat53.module".math.log
    end

    return function (n)
        if n == 0 then return "0" end
        local order = math.floor(log(n, 2) / 10)
        if order > 5 then order = 5 end
        n = math.ceil(n / 2^(order*10))
        return string.format("%d%s", n, suffixes[order])
    end
end)()

--[[ END FILE ]]--
return utils