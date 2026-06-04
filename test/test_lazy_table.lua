local table = require'./lib/utils'.table

local function printtable(tb)
    for k, v in pairs(tb) do
        print(tostring(k)..'\t'..tostring(v))
    end
end

local tb = table.lazy {
    time = os.time();
    ['method'] = function(self)
        printtable(self)
        return tostring(self.time)
    end;
}
print(tb.method)
table.print(getmetatable(tb).getters)