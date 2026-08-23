--[[
    Bootstrapping
--]]
local options = require'utils'.readargs { table.unpack(arg) } (function(options, v)
    local k, vs = table.unpack(v)
    if k == '--' or k == '' then 
        options.prefix = assert(vs[1], 'prefix is required (the base path of c modules)');
    elseif k == '-m' or k == '--method-name' then
        options.method_name = assert(vs[1], 'C method name cannot be empty')
    end
    ::continue::
end)

--[[
    Utilities
--]]
local msg = function(leading, param, ...) 
    if param 
    then io.stderr:write(string.format(leading, param, ...)) 
    else io.stderr:write(leading) 
    end
end
local write = function(...) io.stdout:write(...) end
local fmt = string.format
local noop = function() end

local function nm(obj)
    local p, err = assert(io.popen('nm '..obj, 'r'))
    local lines = {}
    for line in p:lines() do
        local fields = {}
        for field in line:gmatch('[^%s]+') do
            table.insert(fields, field)
        end
        table.insert(lines, fields)
    end
    p:close()
    return lines
end

--[[
    MAIN

    It's a template to output particial C source codes to be concat
    to a static compiled lua bundle.
--]]
msg('out_clib: library code prefix "%s"\n', options.prefix)
local modules = {}
for line in io.stdin:lines() do
    local dlpath = string.format('%s/%s', options.prefix, line)
    local main_module_name   = line:sub(1, ({line:find('[^%.]+$')})[1] - 2):gsub('/', '.')
    local main_module_c_name = 'luaopen_'..main_module_name:gsub('%.', '_')
    msg('out_clib: inspect "%s", name "%s": %s\n', main_module_name, main_module_c_name ,dlpath)
    
    local p_symb = '^_'..main_module_c_name
    for _, symbol in ipairs(nm(dlpath)) do
        if symbol[2] ~= 'T' then goto continue end;
        local c_name = symbol[3]
        local idxs, idxe = c_name:find(p_symb)
        if not idxs then goto continue end

        --- Get module name from C function symbol
        local sub_module_name = c_name:sub(idxe + 1):gsub('_','.')
        if sub_module_name == '' then
            table.insert(modules, {main_module_name, c_name})
            msg('out_clib:    main module "%s" entry point "%s"\n', main_module_name, c_name)
        else
            sub_module_name = main_module_name .. sub_module_name
            table.insert(modules, {sub_module_name, c_name})
            msg('out_clib:     sub module "%s" entry point "%s"\n', sub_module_name, c_name)
        end
        ::continue::
    end
end
msg('out_clib: total %d modules\n', #modules)

if   options.method_name
then write(fmt('void %s(lua_State *L) ', options.method_name))
end
write[[{
    lua_newtable(L);

]]
for _, module in ipairs(modules) do
    local modname, c_name = table.unpack(module)
    c_name = c_name:gsub('^_', '') --[[ remove the leading _ ]]
    write(fmt('    extern int %s (lua_State* L);\n', c_name))
    write(fmt('    lua_pushcfunction(L, %s);\n', c_name))
    write(fmt('    lua_setfield(L, -2, "%s");\n\n', modname))
end
write(fmt('    // Summary: Total %s modules\n', #modules))
write('}\n')