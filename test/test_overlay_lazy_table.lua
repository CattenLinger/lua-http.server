local extable = require'./lib/utils'.table

local lazytbl = extable.computed {
    store = { time=os.time() }
}

local tbl = extable.overlay { 
    lazytbl;
    { 
        get_stored_time = function(self)
            return self.store.time
        end
    };
};

print("time: "..tostring(tbl:get_stored_time()))