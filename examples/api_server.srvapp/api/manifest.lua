local lfs = require'lfs'
local promise = require'cqueues.promise'

local cache_path = './temp/manifest.cache'
if not lfs.attributes('./temp', 'mode') then assert(lfs.mkdir('./temp')) end
local function cache_file_exists()
    return 'file' == lfs.attributes(cache_path, 'mode')
end

-- HTTP client
local http_client = require 'http.request'
local function client_get(uri)
    local client_req = http_client.new_from_uri(uri)
    client_req.headers:upsert(":method", "GET")
    local res_headers, res_stream = client_req:go(10)
    if not res_headers then
        error('request end without finish: '..tostring(res_stream))
    end
    return res_headers, res_stream
end

local clock = require'utils'.clock
--[[ Debouncer ]]

local new_dl_report do
    local __proto = { subject = '(nil)'; acc = 0; start = 0; clock = clock; }
    function __proto.inc(self, inc)
        self.acc = self.acc + inc
        return self.acc
    end
    function __proto.report(self)
        local subject, acc, start = self.subject, self.acc, self.start
        local now = clock()
        local delta = now - start
        if delta <= 0 then delta = 30; end
        local speed = (acc / delta * 1000) / 1024
        log:trace('Downloading "%s": %02.2fKB/s', subject, speed)
    end

    local __mt = {
        __index = __proto;
        __call = function(self, inc)
            self:inc(inc)
            self:report()
        end
    }
    function new_dl_report(options)
        options = options or {}
        setmetatable(options, __mt)
        options.start = options.clock()
        return options
    end
end

local loading_deferred

-- CASE 1: request is processing
-- wait the loading process finish
local function response_deferred_data(_, response)
    local value = loading_deferred:get(10)
    response:status(200)
            :header('x-lua-http-server', 'cached=true; deferred;')
            :content_type('text/plain;charset=utf-8')
            :finish(io.open(value))
    return
end

-- CASE 2: Cache file exists
-- just open and read the file
local function response_cached_data(_, response)
    response:status(200)
            :header('x-lua-http-server', 'cached=true')
            :content_type('text/plain;charset=utf-8')
            :finish(io.open(cache_path, 'r'))
    return
end

-- CASE 3: file not exists
-- Create a promise, and request the remote, then return
local function response_remote_date(_, response, uri)
    local cache, err = io.open(cache_path, 'w')
    if not cache then error('open cache file failed: '..err) end

    loading_deferred = promise.new()

    local ok, _, res_stream = pcall(client_get, uri)
    if not ok then -- request failed
        local err_msg = res_stream or 'client request failed'
        loading_deferred:set(false, nil, err_msg)
        loading_deferred = nil
        error(err_msg)
    end

    local debounce = require'lib.debouncer'()
    local report   = new_dl_report()

    local function save_and_response(writer)
        local bulk_ok, bulk_err = pcall(function()
            local buf, r_err, errno
            repeat
                buf, r_err, errno = res_stream:get_body_chars(256, 10)
                if not buf then break end

                writer(buf); cache:write(buf);
                if not debounce() then report(#buf) end
            until not buf
        end)
        cache:close()

        if not bulk_ok then
            loading_deferred:set(false, bulk_err)
            os.remove(cache_path)
            error(bulk_err)
        end
        report(0)
        log:info('Downloading "%s" Finished', uri)
        loading_deferred:set(true, cache_path)
        loading_deferred = nil
    end
    --local ok, err = res_stream:save_body_to_file(cache, 30)
    --if not ok then error('failed to write file: '..err) end
    response:status(200)
            :content_type('text/plain;charset=utf-8')
            :finish(save_and_response)
end

local uri = 'https://luarocks.org/manifest'

return function(request, response)
    if 'GET' ~= request.method then
        response:status(405)
                :content_type('text/plain;charset=utf-8')
                :finish()
        return
    end

    if loading_deferred ~= nil
    then goto deferred
    elseif cache_file_exists()
    then goto cached
    else goto default
    end

    ::deferred:: do return response_deferred_data(request, response)    end
    ::cached::   do return response_cached_data(request, response)      end
    ::default::  do return response_remote_date(request, response, uri) end
end