local cqueues = require'cqueues'

local parent_cq = cqueues:new()
local child_cq  = cqueues:new()

local function child_job()
    cqueues.sleep(3)
    print(string.format('[Child CQ ] Child wake: %d', 3))
end

local function parent_job()
    cqueues.sleep(2)
    print(string.format('[Patent CQ] Parent wake: %d', 2))
end

local function otherjobs()
    cqueues.sleep(1)
    print(string.format('[Parent CQ] other jobs: %d', 1))
end

child_cq:wrap(child_job)

parent_cq:wrap(parent_job)
         :wrap(otherjobs)
         :wrap(function()
            print('[Parent CQ] Start dispatch child ')
            assert(child_cq:loop())
        end)

assert(parent_cq:loop())