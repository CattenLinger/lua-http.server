local utils = {}

-- Build a simple logger
utils.simple_log = function(target)
	local stream = target or io.stderr
	if not stream.write then error("log constructor target must be a stream") end
	function write(...) stream:write('[', os.date("%d/%b/%Y:%H:%M:%S %z") ,'] ' ,...); end

	return function(leading, ...)
		if not leading then return write('\n') end
		local arg = ...
		if arg == nil then return write(leading, '\n') end
		write(string.format(leading, ...), '\n')
	end
end

-- Convert byte to human friendly format
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

-- Search a jump table uses string as key with non
-- string value
function utils.search_jump_table(jtb, key, max_jump)
    local cnt = max_jump or 3
    local k = key
    ::search::
    local v = jtb[k]
    if type(v) ~= 'string' then return v, k; end

    if cnt <= 0 then error("jump table max redirect reached"); end
    k = v
    cnt = cnt - 1
    goto search
end

-- Parse command line arg to a list of 
-- groups
function utils.arg_parse(args)
    local arg_list, props = {}, {}
    while true do
       local v = table.remove(args)
       if v == nil then break; end

       if string.sub(v, 1, 1) == '-' then
           table.insert(arg_list, { v, props })
           props = {}
           goto continue
       else
           table.insert(props, v)
       end
       ::continue::
    end

    if #props > 0 then table.insert(arg_list, { '', props }); end
    return arg_list
end

---
--- @return number result of os.clock() * 100 (seconds)
function utils.clock()
	return os.clock() * 100
end

return utils