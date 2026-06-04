function class(name)
    local __mt__ = { 
        name=name, members={}, statics={
            is = function(tb)
                local mt = getmetatable(tb)
                if not mt then return false; end
                return name == mt.class.name
            end;

            init = function(self, ...) 
            end;
        }
    }
    __mt__['__index'] = setmetatable({}, { __index=__mt__.statics })

    return function(options)
        assert(type(options) == 'table', "class definition table is required")

        local members = __mt__.members
        local statics = __mt__.statics

        for k, v in pairs(options) do
            if k == ':init' then
                statics.init = v
                goto continue
            end

            members[k] = v
            ::continue::
        end

        assert(type(statics.init) == 'function', 'init of '..__mt__.name..' is not a function')
        __mt__['__call'] = function(_, ...)
            local d = setmetatable({}, { 
                __index = members,
                class = __mt__
            })
            statics.init(d, ...)
            return d
        end

        return setmetatable({}, __mt__)
    end
end

local Request = class 'http.server.request' {
    [':init'] = function (self, ...)
        self.method = 'GET'
    end;

    print_method = function(self)
        print("My method is: "..self.method)
    end
}

local req = Request()
req:print_method()