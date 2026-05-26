
--local extext = require'utils'.text
local table = require'utils'.table
local http_util = require'http.util'

local function parse_mime(str)
    if not str or str == '' then return nil, 'mime string is empty' end
    local fields = table.collect(string.gmatch(str, '[^;]+'))
    if not string.find(fields[1], '[^/]+/[^/]+') then
        return nil, 'invalid mime format'
    end
    return fields
end

local function check_content_type(str)
    local fields = parse_mime(str)
    if not fields then return false end
    return fields[1] == 'application/x-www-urlencoded-form'
end

local function check_auth(request)
    local auth = request.headers:get'authorization'
    log('[check_auth] Auth header: %s', auth)
    local fields = table.collect(string.gmatch(auth, '[^%s]+'))
    if not fields[1] then return nil end
    return fields
end

local function unauthed(response, msg)
    response:status(403)
            :content_type('text/plain;charset=utf-8')
            :finish('Forbidden: '..(msg or ''))
end

local function bad_request(response, msg)
    response:status(400)
            :content_type('text/plain;charset=utf-8')
            :finish('Bad Request: '..(msg or ''))
end

local function on_get(request, response)
    local auth = check_auth(request)
    if not auth then return unauthed(response, 'no header') end

    local auth_type, principal = table.unpack(auth)
    if not (auth_type and auth_type:lower() == 'basic' and principal) then
        return bad_request(response, 'bad auth header')
    end
    local credential = table.collect(string.gmatch(http_util.decodeURIComponent(principal), '[^:]+'))
    if not credential then return unauthed(response, 'no credential') end

    local body = string.format(
            'User: %s\nPass: %s\n',
            tostring(credential[1]),
            tostring(credential[2])
    )
    response:status(200)
            :content_type('text/plain;charset=utf-8')
            :finish(body)
end

local digest    = require'openssl.digest'
local base64    = require'basexx'.to_base64
local function on_post(request, response)
    if not check_content_type(request.content_type) then
        return bad_request(response, 'invalid content type')
    end

    local body = request.stream:get_body_as_string(10)
    if not body or body == '' then return bad_request(response, 'no body') end
    log:debug('[POST] /auth , body: %s', body)
    local params = table.collect(http_util.query_args(body))
    if #params == 0
    then return bad_request(response, 'missing body params')
    end

    local form = table.from_entries(params)
    if not (form.username and form.password)
    then return bad_request(response, 'username and password required')
    end

    local password_hash = digest.new('md5'):update(form.password):final()
    local resp_body = string.format(
            "User: %s\nPass: %s\n",
            form.username,
            base64(password_hash)..' (MD5)'
    )
    response:status(200)
            :content_type('text/plain;charset=utf-8')
            :finish(resp_body)
end

local method_mapping = { GET = on_get; POST = on_post; }

return function(request, response)
    local handler = method_mapping[request.method]
    if handler then return handler(request, response) end

    response:status(405)
            :content_type('text/plain;charset=utf-8')
            :finish()
end