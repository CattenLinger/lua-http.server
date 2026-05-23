--[[ Server request wrapper ]]
local http_util = require "http.util"
local lpeg      = require "lpeg"
local uri_patts = require "lpeg_patterns.uri"
local uri_ref   = uri_patts.uri_reference * lpeg.P(-1)

local table   = require'utils'.table
local webroot = CONFIG.root_path

local getters = {}
local __mt = { __index=getters }

function getters.headers(self)
    return assert(self.stream:get_headers())
end

function getters.method(self)
    return assert(self.headers:get':method')
end

function getters.uri(self)
    return assert(self.headers:get':path')
end

function getters.path(self)
    local path = self.uri
    local uri_t = assert(uri_ref:match(path), "invalid path")
    return http_util.resolve_relative_path("/", uri_t.path)
end

function getters.query_string(self)
    local uri = self.uri
    local idx = string.find(uri, '?', 1, true)
    if not idx then return '' end
    return string.sub(uri, idx + 1)
end

function getters.query(self)
    local query_string = self.query_string
    local queries = {}
    if query_string == '' then return queries end
    for k, v in http_util.query_args(query_string) do
        table.insert(queries, { k, v})
    end
    return queries
end

function getters.real_path(self)
    return webroot .. http_util.decodeURIComponent(self.path)
end

return function (server, stream)
    return table.lazy(setmetatable({ stream = stream }, __mt ));
end