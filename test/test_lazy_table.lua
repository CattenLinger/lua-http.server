local table = require'src/utils'.table

local function printtable(tb)
    for k, v in pairs(tb) do
        print(tostring(k)..'\t'..tostring(v))
    end
end

local getters = {
    ['method'] = function(self)
        printtable(self)
        return tostring(os.time())
    end;
}
local __mt = {__index=getters}
local getters2 = setmetatable({ time = os.time(); }, __mt)

local tb = table.lazy(getters2)

print('method:', tb.method)
print('time  :', tb.time)

table.print(getmetatable(tb).getters)