--[[
    Bootstrapping
--]]
local options = require'utils'.readargs { table.unpack(arg) } (function(options, v)
    local k, vs = table.unpack(v)
    if k == '--' or k == '' then 
        options.prefix = assert(vs[1], 'prefix is required (the base path of lua modules)');
    elseif k == '-c' or k == '--compile' then
        options.compile = assert(vs[1], 'luac command is require')
    elseif k == '-m' or k == '--method-name' then
        options.method_name = assert(vs[1], 'C method name cannot be empty')
    elseif k == '--hex-dump' then
        options.hexdump_only = true
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

---Dump string to hex
---
local hexdump = (function(line_width, indent)
    local numtab = {}
    for i = 0, 255 do
        numtab[string.char(i)] = ("%-3d,"):format(i)
    end
    local line_pattern = ("."):rep(line_width * 4)
    local line_template = "%0\n"..(' '):rep(indent)

    return function(str)
        return (str:gsub(".", numtab):gsub(line_pattern, line_template))
    end
end)(30 --[[ unit count ]], 8 --[[ indent ]])

if options.hexdump_only then
    print(hexdump(io.stdin:read('*all')))
    os.exit(0)
end

---Different way to open a stream of codes
local open_stream = setmetatable({
    ---Open a stream of compiled lua bytecode
    compile = function(path)
        local cmd = string.format('%s -o - "%s"', options.compile, options.prefix..path)
        return assert(io.popen(cmd,'r'))
    end;

    ---Open a stream of raw file bytecode
    file = function(path)
        return assert(io.open(options.prefix..path, 'rb'))
    end;
}, { __call=function(self, key) return self[key] or noop end })

--[[
    MAIN

    It's a template to output particial C source codes to be concat
    to a static compiled lua bundle.
--]]
msg('out_lualib: library code prefix "%s"\n', options.prefix)
if   options.method_name
then write(fmt('void %s(lua_State *L) ', options.method_name))
end
write[[{
    lua_newtable(L);

]]
local counter = 0
for line in io.stdin:lines() do
    local filename = string.gmatch(line, '[^%s]+')()
    if #filename <= 0 then goto continue end

    local fd if options.compile
    then  fd = open_stream'compile'(filename)
    else  fd = open_stream'file'(filename)
    end

    local block_name = string.format('lualib_bytecode_%02X', counter)
    local modname    = string.gsub(filename, '%.lua$', ''):gsub('/', '.')
    msg('out_lualib: Dump "%s" as "%s" (%s)\n',modname,block_name,type(fd))
    write(fmt('    static const unsigned char %s[] = {\n', block_name))
    write(    '        ',hexdump(fd:read("*all")))
    write(    '    };\n')
    write(fmt('    lua_pushlstring(L, (const char*)%s, sizeof(%s));\n', block_name, block_name))
    write(fmt('    lua_setfield(L, -2, "%s");\n\n', modname))
    fd:close()

    counter = counter + 1
    ::continue::
end
write(fmt('    /* SUMMARY: Total %3d modules */\n', counter))
write('}\n')
