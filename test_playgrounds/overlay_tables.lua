
local overlay_tables_for = require'./lib/utils'.overlay_tables_for

local layers = { 
    { key1 = 'A'; };
    { key2 = 'B'; };
    { key3 = 'C'; };
}

local target = {
    key0 = 'Z'
}

local tbl = overlay_tables_for(target, layers);
for i=0, 3 do
    print(tbl['key'..tostring(i)])
end