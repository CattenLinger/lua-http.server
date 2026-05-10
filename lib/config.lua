local arg_parse = require'utils'.arg_parse
local search_jump_table = require'utils'.search_jump_table

local function arg_process(arg_list, cfg, spec_tbl)
    local escaped, remains = {}, {}

	local function check_arg_size(key, values, arg_size)
		-- If values list length is less than arg_min, it will exit with error.
		--
		-- If arg_max is nil, it means there is no upper limit for the number of argument values,
		-- and use value list's length as arg_max.
		--
		-- It will return the arg_min and arg_max for later use.
        --
		local arg_min, arg_max = table.unpack(arg_size or { })
		-- a nil arg_min means argument values are optional.
        if arg_min ~= nil and #values < arg_min then
            error(string.format('"%s" requires %d values\n', key, arg_min))
        end
		if not arg_max then arg_max = #values; end
		return arg_min, arg_max
	end
	
    --[[ Main ]]--
    do
        ::continue_ProcessEachProp::
        local props = table.remove(arg_list)
        if not props then goto finish_ProcessEachProp; end

        local key, values = table.unpack(props)
        if key == '' then
            table.insert(remains, props)
            goto continue_ProcessEachProp
        end

        local arg_specs = search_jump_table(spec_tbl, key, 3)
        if not arg_specs then
            table.insert(remains, props)
            goto continue_ProcessEachProp
        end

        -- If values list length is less than arg_min, it will exit with error.
        local arg_min, arg_max = check_arg_size(key, values, arg_specs.size)
        
        local values_need = {}
        for i=1, arg_max do table.insert(values_need, table.remove(values)); end
        
        -- take remaining values as escaped args, which will be passed to next processor
        while #values > 0 do table.insert(escaped, table.remove(values)); end

        local set_prop = arg_specs.set_prop
        if set_prop then
            local set_key, set_value = table.unpack(set_prop)

            if not set_key then goto end_set_key; end
            -- if set_value is not specified, it will use values_need as the value to set.
            -- if set_value is specified but values_need is not empty, use values_need.
            if #values_need > 0 then set_value = values_need; end

            -- if the set_value is a table and it only accept single value,
            -- take the first value
            if type(set_value) == 'table' and arg_max == 1 then
                set_value = set_value[1];
            end

            cfg[set_key] = set_value
            ::end_set_key::
        end
        
        goto continue_ProcessEachProp
        ::finish_ProcessEachProp::
    end

	return remains, escaped
end

local DefaultConfig = {
    binary_home = os.getenv('LUA_HTTP_SERVER_HOME');

    host = {'localhost'};
    port = '8000';

    root_path   = '.';
    handler_dir = 'handlers/';
}
local CfgProto = {}
do
    function CfgProto.resolve(path)
    
    end
end

local arg_meta = {
    {
        ['--host'] = {
            desc = 'Address to listen to';
            size = { 1 }, set_prop = { 'host' }
        };

        ['--port'] = {
            desc = 'Port to listen to';
            size = { 1, 1 }, set_prop = { 'port' }
        };

        ['--root'] = {
            desc = 'Web root';
            size = { 1 }, set_prop = { 'root_path' }
        };

        ['-d'] = '--root';
        ['-p'] = '--port';
        ['-h'] = '--host';

        ['--handler-path'] = {
            desc = 'handler folder path';
            size = { 1, 1 }, set_prop = { 'handler_dir' }
        };
        ['-dH'] = '--handler-path';

        ['--no-page-cache'] = {
            desc = 'Disable page caching';
            size = { 0 }, set_prop = { 'no_page_cache', true }
        };
        
        ['--no-handler-cache'] = {
            desc = 'Disable handler caching';
            size = { 0 }, set_prop = { 'no_handler_cache', true }
        };

        ['--no-handler-config'] = {
            desc = 'Disable handler config';
            size = { 0 }, set_prop = { 'no_handler_config', true }
        };
        

        ['-nCP'] = '--no-page-cache';
        ['-nCH'] = '--no-handler-cache';
        ['-nPH'] = '--no-handler-config';

        ['--debug'] = {
            desc = 'Enable all debug features';
            size = { 0 }, set_prop = { 'debug', true }
        };
        ['-d'] = '--debug'
    };
    function (config)

    end;
}

return function(args)
    local cfg = setmetatable({}, { __index = DefaultConfig })
    local arg_spec, post_process = table.unpack(arg_meta)
    local arg_list = arg_parse(args)
    local remain, escaped = arg_process(arg_list, cfg, arg_spec)
    post_process(cfg)
    cfg._args = { table.unpack(args); remain=remain; escaped=escaped; }
    return cfg
end