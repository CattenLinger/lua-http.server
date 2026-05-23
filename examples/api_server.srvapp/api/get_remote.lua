local request, response = ...;
local lfs = require'lfs'
local cache_path = CONFIG.root_path..'/get_remote.cache'

if 'file' == lfs.attributes(cache_path, 'mode') then
    response:status(200)
        :content_type('text/plain;charset=utf-8')
        :finish(io.open(cache_path, 'r'))
    return
end

local client = require 'http.request'
--local http_util = require 'http.util'

local cache, err = io.open(cache_path, 'w')
if not cache then error('open cache file failed: '..err) end

local uri = 'https://luarocks.org/manifest'
local client_req = client.new_from_uri(uri)
client_req.headers:upsert(":method", "GET")
local res_headers, res_stream = client_req:go(10)
if not res_headers then error('request end without finish') end
local clock = require'utils'.clock_ms

local last_report = 0
local function debounce(now)
    if (now - last_report) < 1000 then return true end;
    last_report = now;
end

local downloaded_bytes, start_time = 0, clock()
local function report(acc)
    downloaded_bytes = downloaded_bytes + acc
    local now = clock()

    local delta = now - start_time
    if delta <= 0 then delta = 30; end
    local speed = (downloaded_bytes / delta * 1000) / 1024
    log:trace('Downloading "%s": %02.2fKB/s', uri, speed)
end
local function save_and_response(write)
    local buf, err, errno
    repeat
        buf, err, errno = res_stream:get_body_chars(256, 10)
        if not buf then break end
        write(buf); cache:write(buf);
        if not debounce(clock()) then report(#buf) end
    until not buf
    cache:close()
    report(0)
    if err then error(err) end
    log:info('Downloading "%s" Finished', uri)
end
--local ok, err = res_stream:save_body_to_file(cache, 30)
--if not ok then error('failed to write file: '..err) end
response:status(200)
        :content_type('text/plain;charset=utf-8')
        :finish(save_and_response)