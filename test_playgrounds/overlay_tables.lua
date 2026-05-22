
local extable = require'./lib/utils'.table

local tbl = extable.overlay {
    { key0 = 'Z'; };
    { key1 = 'A'; };
    { key2 = 'B'; };
    { key3 = 'C'; };
};
for i=0, 3 do
    print(tbl['key'..tostring(i)])
end