local Request = require 'http.request'
local cache_path = './temp/request.cache'
local lfs = require'lfs'

function outfile(file)
    for line in file:lines() do print(line) end
    file:close()
    return
end

if 'file' == lfs.attributes(cache_path, 'mode') then
    outfile(io.open(cache_path, 'r'))
    return
end


local uri = 'https://luarocks.org/manifest'
local request = Request.new_from_uri(uri)
request.headers:upsert(":method", "GET")
local res_headers, res_stream = request:go(10)
if not res_headers then error('request end without finish') end

local cache, err = io.open(cache_path, 'w')
if not cache then error(err) end
local ok, err = res_stream:save_body_to_file(cache, 10)
if not ok then error('could not save request content from file: '..err) end
cache:seek('begin')
outfile(cache)
