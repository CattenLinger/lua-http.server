local template = {}

function template.escape(data)
    return tostring(data == nil and "" or data):gsub("[\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    })
end

local wrapper_fn do
    local wrapper, err = load(
            [[return function(_ENV,exec,...) local f=...; f(exec, _ENV); end]],
            "wrapper", "t"
    )
    if not wrapper then error(err) end
    wrapper_fn = wrapper()
end

local table = require'utils'.table

function template.print(data, args, callback)
    local callback = callback or print

    local env = table.overlay { args or {}; _G; }

    local function exec(ins)
        if type(ins) ~= "function" then
            return callback(tostring(ins == nil and "" or ins))
        end
        -- if type(data) == "function"
        return wrapper_fn(env, exec, ins)
    end
    exec(data)
end

local template_entry do
    local s = "function(_"
    if not _ENV
    then s = s .. ') '
    else s = s .. ",_ENV) "
    end
    template_entry = s
end

function template.parse(data, minify)
    local str =
    "return " .. template_entry ..
        "function __(...)" ..
            "_(require('template').escape(...))" ..
        "end " ..
        "_[=[" ..
        data:
            gsub("<%%=", "]=]_("):
            gsub("<%%", "]=]__("):
            gsub("%%>", ")_[=["):
            gsub("<%?", "]=] "):
            gsub("%?>", " _[=[") ..
        "]=] " ..
    "end"

    if minify then
        str = str:
        gsub("^[ %s]*", ""):
        gsub("[ %s]*$", ""):
        gsub("%s+", " ")
    end
    return str
end

--[[
  `loadstring` was deprecated since 5.2, use `load` instead
  (see: https://www.lua.org/manual/5.2/manual.html#8.2)
]]--
local loadstring = loadstring or function(str, chkn)
    return load(str, chkn or str, 't') -- We will pass _ENV manually
end

function template.compile(...)
    local f, err = loadstring(template.parse(...))
    if err then error(err) end
    return f()
end

function template.render(data, args)
    local parts = {}
    local i = 0

    template.print(data, args, function(p)
        i = i + 1
        parts[i] = p
    end)

    return table.concat(parts)
end

return template
