package.path = './lua/?.lua;'..package.path

local cqueues = require'cqueues'
local cq = cqueues.new()
local clock = require'utils'.clock
cq:wrap(function()
    for _=1, 10 do
        cqueues.sleep(1)
        print('Clock: '..tostring(clock()))
    end
end):loop()