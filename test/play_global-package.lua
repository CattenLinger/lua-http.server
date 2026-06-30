local GLOBAL = _G
local function print_table(tbl)
    for key, value in pairs(tbl)
    do print(tostring(key), '=', tostring(value))
    end
end
print_table(GLOBAL)

print("======= Remove unsafe values ")
local unsafe_values = {
    --[[Debug]]--
    'debug';
    --[[Code execution]]--
    'load', 'loadfile', 'dofile', 'require', 'package';
    --[[Meta Programming]]--
    'setmetatable', 'getmetatable';
    --[[System facility]]--
    'os', 'io';
}
local ENV_unsafe = {}
setmetatable(_ENV, { __index=ENV_unsafe, __newindex=function()  end })
for _, key in ipairs(unsafe_values) do
    rawset(ENV_unsafe, key, rawget(_ENV, key))
    rawset(_ENV, key, nil)
end
print_table(GLOBAL)
print("======== unsafe values")
print_table(ENV_unsafe)

print("======== package")
print_table(ENV_unsafe.package)


