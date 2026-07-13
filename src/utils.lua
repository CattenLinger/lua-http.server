local MODULE_NAME, FILE_PATH = ...
local utils = setmetatable({}, {
    __index=function(_, key)
        return require(MODULE_NAME..'.'..key)
    end;
})

--- Get the current time in seconds.
--- @return number @the result of os.clock() * 100 (seconds)
function utils.clock() return os.time() end
--- Get the current time in millis.
---@return number 
function utils.clock_ms() return os.clock() * 100000 end

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

--[[ END FILE ]]--
return utils