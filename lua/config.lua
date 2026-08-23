local arg_parse = require'utils'.arg_parse
local string    = require'utils'.text
local table     = require'utils'.table
local os        = require'utils'.os

local unpack    = table.unpack
local write     = function(...) io.stdout:write(...) end

local M = {}

--[[
    If values list length is less than arg_min, it will exit with error.
    If arg_max is nil, it means there is no upper limit for the number of argument values,
    and use value list's length as arg_max.

    It will return the arg_min and arg_max for later use.
--]]
local function check_arg_size_(key, values, arg_size)
    local arg_min, arg_max = table.unpack(arg_size or { })
    -- a nil arg_min means argument values are optional.
    if arg_min ~= nil and #values < arg_min then
        error(string.format('"%s" requires %d values\n', key, arg_min))
    end
    if not arg_max then arg_max = #values; end
    return arg_min, arg_max
end

---See README.MD about the `options` format of `.appmeta`
local function arg_process(arg_list, cfg, spec_tbl)
    local escaped, remains = {}, {}
    local spec_idx = {}
    for _, e in ipairs(spec_tbl) do
        for _, o in ipairs(e) do spec_idx[o] = e end
    end
	
    --[[ Main ]]--
    while true do
        local props = table.remove(arg_list)
        if not props then break end

        local key, values = unpack(props)
        if key == '' then table.insert(remains, props); goto continue; end

        local arg_specs = spec_idx[key]
        if not arg_specs then table.insert(remains, props); goto continue; end

        -- If values list length is less than arg_min, it will exit with error.
        local _, arg_max = check_arg_size_(key, values, arg_specs.size)

        local values_need = {}
        for _=1, arg_max do table.insert(values_need, table.remove(values)); end
        
        -- take remaining values as escaped args, which will be passed to next processor
        while #values > 0 do table.insert(escaped, table.remove(values)); end

        local set_prop = arg_specs.set_prop
        local set_key, set_value
        if set_prop then
            set_key, set_value = table.unpack(set_prop)

            if not set_key then goto end_set_key; end -- bad format, ignore

            -- Must be an array of values
            if type(set_value) ~= 'table' then set_value = { set_value } end

            -- if `set_value` is not specified, it will use `values_need` as the value for set.
            -- if `set_value` is specified but `values_need` is not empty, use `values_need`.
            if #values_need > 0 then set_value = values_need; end
            
            ::end_set_key::
        else
            set_key, set_value = key, values
        end
        
        -- add to app_cfg
        local origin = cfg[set_key]
        if origin ~= nil then
            -- no more empty value
            if #set_value == 0 then goto continue end

            if type(origin) ~= 'table' then origin = { origin } end
            for _, i in ipairs(set_value) do table.insert(origin, i) end
            cfg[set_key] = origin
        else
            -- unwrap
            if #set_value == 1 then set_value = set_value[1] end
            cfg[set_key] = set_value
        end
        
        ::continue::
    end

	return remains, escaped
end

--[[
    DSL env mt & env factory
--]]
local create_appmeta_env = (function()
    local keywords = {};
    function keywords.title(self, _, value) return rawset(self, 'title', value) end;
    function keywords.name(...) return keywords.title(...) end;
    function keywords.desc(...) return keywords.description(...) end
    function keywords.description(self, _, value)
        local key = 'description'
        if type(value) == 'table' 
        then value = table.concat(value, '\n')
        else value = tostring(value)
        end
        rawset(self, key, value)
    end;
    function keywords.opts(self, _, value) return rawset(self, 'options', value) end;

    local preloads = { string=string; tostring=tostring; }

    local appmeta_mt_ = {
        __index    = function(self, key) return preloads[key] end;
        __newindex = function(self, key, value)
            local name = string.lower(key)
            local handler = keywords[name]
            if not handler then return rawset(self, key, value) end
            handler(self, key, value)
        end
    }

    return function(filepath)
        local env = setmetatable({}, appmeta_mt_)
        local cfger, err = loadfile(filepath, 't', env)
        if not cfger then return nil, err end

        local ok, cfgval = pcall(cfger)
        if not ok then return nil, cfgval end
        return env
    end
end)()

--[[
    Help Printer And Formatter
--]]
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
            write(string.format("  %s%s\t%s\n", k, string.nchar(mxlen - klen), desc))
        end
        return cnt
    end

    local function print_appmeta(cfg)
        local resolver = os.path(cfg.handler_dir)
        local env, err = create_appmeta_env(resolver:resolve('.appmeta'))
        if not env then
            write('\n', '[i] Show WebApp Info: could not locate any vaild meta under suit location.\n')
            write('[i] Help info of this WebApp is not available.\n')
            write('[i] Reason: ', tostring(err), '\n\n')
            return
        end

        local title   = env.title       or 'Path: '..tostring(resolver)
        local desc    = env.description or '(app has no description)'
        local spectbl = env.options     or {}

        local linebuf = { ':::::::: WebApp Info ::::::::' }
        if title then table.insert(linebuf, title) end
        table.insert(linebuf, desc)
        local has_options = #spectbl > 0
        if not has_options then table.insert('App has no avaliable options.') end
        write(table.concat(linebuf, '\n'), '\n')
        if not has_options then return end
        write('Options: \n')
        print_spec_tbl(spectbl)
    end

    local banner = table.concat({
        'A simple and dynamic http server in lua with lua-http';
        'Usage: http-server [options]';
        '';
    }, '\n')

    local print_dbg_info = function()
        local pkg = require'package'

        write(
            ':::::::: Debug Info ::::::::\n',
            string.format('Lua Version : %s\n', _VERSION),
            string.format('Lua Path    : %s\n', pkg.path),
            string.format('Lua C Path  : %s\n', pkg.cpath),
            string.format('Server Home : %s\n', pkg.homedir)
        )
    end

    print_help = function(config, spec_meta)
        write(banner)
        local spec_tbl = unpack(spec_meta)
        write('Options:\n')
        print_spec_tbl(spec_tbl)

        if config.debug then print_dbg_info() end

        if not config.handler_dir then return end
        print_appmeta(config)
    end 
end

--[[
    Server arg table & arg post-process
--]]
local arg_meta = {
    {
        {   '--host', '-h'; size = { 1 }, set_prop = { 'host' };
            desc = { 'Address to listen to, default is "localhost"'; };
        };
        {   '--port', '-p'; size = { 1, 1 }, set_prop = { 'port' };
            desc = 'Port to listen to, default is "8000"';
        };
        {   '--suit', '-s', '--handler-path'; size = { 1, 1 }, set_prop = { 'handler_dir' };
            desc = { 'Handler folder path';
                     'Server will read the `.webapp.lua`(or `.config.lua` for compatibility) ';
                     'under this path for request processor and error handler, see README.MD'; };
        };
        {   '--debug' ; size = { 0 }, set_prop = { 'debug', {} };
            desc = { 'Enable debug feature flags. Can use multiple flags together.';
                     'Flags: all, request, apploader, api'; };
        };
        {   '--log-level', '-v'; size = { 1 }, set_prop = { 'log_level', 'TRACE' };
            desc = { 'Set log level, 0 to 5 or ERROR,WARN,INFO,DEBUG,TRACE';
                     '0 means disable.' };
        };
        {   '--log-color', '-C'; size = { 0 }, set_prop = { 'log_color', true };
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
            -- Normalize `host` and `port` to array
            if type(config[key]) ~= 'table' then config[key] = { config[key] } end
        end

        if config.debug then
            local debug, ndebug = config.debug, {}
            local t = type(debug)
            if t == 'string' then debug = { debug } end
            if type(debug) == 'table' then
                for _, str in ipairs(debug) do
                    for v in string.gmatch(str, '[^,]+') do
                        table.insert(ndebug, v)
                    end
                end
            end
            config.debug = ndebug
        end
    end;
}

local default_appcfger = function() return {'.config.lua', '.webapp.lua'}, {}, {}; end
local function preprocess_appconfig(cfg)
    cfg.appcfger_ = default_appcfger

    local resolver = os.path(cfg.handler_dir)
    local remain = cfg.args_.remain;
    local meta_path = resolver:resolve('.appmeta')

    -- Check if appmeta exists
    do
        local fd, err =  io.open(meta_path)
        if not fd then return end
        fd:close()
    end

    local env, err = create_appmeta_env(meta_path)
    if not env then write('Load AppMeta failed: ', err, '\n'); os.exit(1) end

    cfg.appcfger_ = function(newcfg)
        local options = env.options or {}
        local appcfg  = newcfg or {}
        local nremian, nescaped = arg_process(remain, appcfg, options)
        appcfg.args_ = { remain=nremian; escaped=nescaped; }
        env.meta_path = meta_path
        local entry_candidates = {}
        local entry_path = env.entry
        if entry_path then 
            table.insert(entry_candidates, entry_path)
        else
            table.insert(entry_candidates, '.config.lua')
            table.insert(entry_candidates, '.webapp.lua')
        end
        return entry_candidates, appcfg, env
    end;
end

function M.from_args(args)
    local cfg = {}
    local arg_spec, post_processor = table.unpack(arg_meta)
    local arg_list = arg_parse(args)
    local remain, escaped = arg_process(arg_list, cfg, arg_spec)
    post_processor(cfg)
    if cfg.help then print_help(cfg, arg_meta); os.exit(0); end
    
    -- save arg parse results
    cfg.args_ = { table.unpack(args); remain=remain; escaped=escaped; }

    if cfg.handler_dir then preprocess_appconfig(cfg) end
    return cfg
end

local mt_ = {
    __index    = M;
    __call     = function(self, ...) return self.from_args(...) end;
    __newindex = (require'utils'.meta).newindex_hook.ignore();
}

return setmetatable({}, mt_)