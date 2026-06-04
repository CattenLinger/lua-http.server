local arg_parse = require'utils'.arg_parse
local extext = require'utils'.text
local table = require'utils'.table
local unpack = table.unpack
local write  = function(...) io.stdout:write(...) end

local M = {}

--[[
    Process arg list according to the spec table
    A spect table is a table that storing meta info
    about options, in format:
    
    {
        -- Definition
        {   '--option', '--alias-1', '-alias-2';
            size={ min_value_count, max_value_count };
            set_prop={ 'prop_name', default_value };
            desc='description';
        };
    }
    
    size & set_prop is optional. size is for validating
    value count for an option. set prop will set the value to 
    the given table
--]]
local function arg_process(arg_list, cfg, spec_tbl)
    local escaped, remains = {}, {}
    local spec_idx = {}
    for _, e in ipairs(spec_tbl) do
        for _, o in ipairs(e) do spec_idx[o] = e end
    end
    --[[
    If values list length is less than arg_min, it will exit with error.
    If arg_max is nil, it means there is no upper limit for the number of argument values,
    and use value list's length as arg_max.
    
    It will return the arg_min and arg_max for later use.
    --]]
	local function check_arg_size(key, values, arg_size)
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

        local key, values = unpack(props)
        if key == '' then
            table.insert(remains, props)
            goto continue_ProcessEachProp
        end

        local arg_specs = spec_idx[key]
        if not arg_specs then
            table.insert(remains, props)
            goto continue_ProcessEachProp
        end

        -- If values list length is less than arg_min, it will exit with error.
        local _, arg_max = check_arg_size(key, values, arg_specs.size)
        
        local values_need = {}
        for _=1, arg_max do table.insert(values_need, table.remove(values)); end
        
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

--[[ Print help text ]]
local print_help do
    local function print_spec_tbl(tbl)
        local cnt, mxlen = 0, 0
        local strbuff = {}
        for _, e in ipairs(tbl) do
            local opts = {}
            for _, opt in ipairs(e) do table.insert(opts, opt) end
            local k = table.concat(opts, ', ')
            local desc = e.desc or 'No description'
            local klen = #k
            if klen > mxlen then mxlen = klen; end
            if type(desc) ~= 'table' then desc = { desc } end
            table.insert(strbuff, { klen, k, tostring(desc[1]) })
            for i=2, #desc do table.insert(strbuff, { 0, '', tostring(desc[i]) }) end
            ::continue::
        end
        for _, i in ipairs(strbuff) do
            local klen, k, desc = unpack(i)
            write(string.format("  %s%s\t%s\n", k, extext.nchar(mxlen - klen), desc))
        end
        return cnt
    end

    local banner = table.concat ({
        'A simple and dynamic http server in lua with lua-http';
        'Usage: http-server [options]';
        '';
    }, '\n')
    function print_help(config, spec_meta)
        write(banner)
        local spec_tbl = unpack(spec_meta)
        write('Options:\n')
        print_spec_tbl(spec_tbl)

        -- TODO: load dynamic help from handler dir
        -- if config.handler_dir then
        -- end
    end 
end

local function no_leading_slash(str)
    if not str then return str end
    if str:sub(1, 1) == '/' then return str:sub(2) end
    return str
end
local function no_tailing_slash(str)
    if not str then return str end
    if str:sub(-1, 1) == '/' then return path:sub(1, #str - 1) end
    return str
end

local os = require'utils'.os
local DefaultConfig = {
    -- Persist bootstrap paths
    lib_path  = package.path;
    lib_cpath = package.cpath;

    host = {'localhost'};
    port = '8000';

    root_path   = '.';
    handler_dir = nil;

    debug = false;
}
local __proto = {
    resolve_root = function (self, path)
        path = no_leading_slash(path)
        return no_tailing_slash(self.root_path)..'/'..os.resolve(path)
    end;

    resolve_handler = function (self, path)
        path = no_leading_slash(path)
        local handler_dir = self.handler_dir
        if not handler_dir then return nil end
        return no_tailing_slash(handler_dir)..'/'..os.resolve(path)
    end;
}
setmetatable(DefaultConfig, { __index=__proto })

local arg_meta = {
    {
        {   '--host', '-h'; size = { 1 }, set_prop = { 'host' };
            desc = { 'Address to listen to, default is "localhost"'; };
        };
        {   '--port', '-p'; size = { 1, 1 }, set_prop = { 'port' };
            desc = 'Port to listen to, default is "8000"';
        };
        {   '--root', '-d'; size = { 1 }, set_prop = { 'root_path' };
            desc = 'Web root, default is "."';
        };
        {   '--handler-path','-s'; size = { 1, 1 }, set_prop = { 'handler_dir' };
            desc = { 'Handler folder path';
                     'Server will read the `.config.lua` under this path for';
                     'request processor and error handler, see README.MD';};
        };
        {   '--debug' ; size = { 0 }, set_prop = { 'debug', true };
            desc = 'Enable all debug features';
        };
        {   '--log-level', '-v'; size = { 1 }, set_prop = { 'log_level', 'TRACE' };
            desc = { 'Set log level, 0 to 5 or ERROR,WARN,INFO,DEBUG,TRACE';
                     '0 means disable.' };
        };
        {   '--log-color', '-vC'; size = { 0 }, set_prop = { 'log_color', true };
            desc = { 'Use colored log';
                     'If the TERM is not colored, this options will be ignored.'};
        };
        {   '--help'; size = { 0 }, set_prop = { 'help', true };
            desc = 'Show help and exit';
        };
    };
    function (config)
        -- normalize options
        for _, key in ipairs { 'host', 'port' } do
            if type(config[key]) ~= 'table'
            then config[key] = { config[key] }
            end
        end
    end;
}

function M.config_from_args(args)
    local cfg = table.overlay { DefaultConfig }
    local arg_spec, post_process = table.unpack(arg_meta)
    local arg_list = arg_parse(args)
    local remain, escaped = arg_process(arg_list, cfg, arg_spec)
    post_process(cfg)
    if cfg.help then print_help(cfg, arg_meta); os.exit(0); end

    cfg._args = { table.unpack(args); remain=remain; escaped=escaped; }
    return cfg
end

return setmetatable({}, {
    __index = M;
    __call  = function(self, ...) return self.config_from_args(...) end;
    __newindex = require'utils'.metatable.newindex_hook.ignore();
})