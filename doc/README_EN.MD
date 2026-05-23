LUA HTTP SERVER
===
[中文版本](/README.MD)

This project is a server modified from the lua-http example HTTP server.

Dependencies:

- [lua-http](https://github.com/daurnimator/lua-http)
- [luafilesystem](https://lunarmodules.github.io/luafilesystem/manual.html) (used by demos under `/examples`)

Running:

```
./bin/http-server [options]

./bin/http-server --help
```

HTTP Server
---

The HTTP server handles requests in the following steps:

1. Inbound: validate the basic request format
2. Select an appropriate handler
3. Execute handler code
4. Outbound: send headers and body (unless the request is HEAD)

`server.lua` implements the inbound and outbound handling; application logic sits on top of it and is considered dynamic. Without any configuration (handler package), the server will simply echo request headers.

Global API & Objects
---

A set of global APIs are provided to let application code interact with the server conveniently.

When using dynamically loaded code, be careful to isolate it properly to protect server context.

- EventQueue: reference to the server's cqueue EventLoop — all coroutine operations should be attached here
- NotifyNextGC: signal to notify the next GC
- Server: the server object
- CONFIG: server configuration

Packages and loading
---

When no handler package is specified the server will only return request headers. To enable richer behavior, pass `--handler-path` to specify a package path.

A package is a folder that contains a `.config.lua`. When a package is used, its path is added to the Lua package path.

`.config.lua` describes how the package should handle requests. Its _ENV is an independent table that inherits from the server context. If the package loads code dynamically, take care to isolate different _ENV tables.

Package lifecycle follows the server process — the package is loaded at startup and will not be updated during runtime. If `.config.lua` changes, the server needs to be restarted for changes to take effect.

Important interfaces
---

The package configuration is the entry point for HTTP requests: it must provide an inbound handler and may optionally provide an error handler. When an HTTP request arrives, the server will call the handler code provided by the configuration. The handler uses two entry points:

1. `on_reply(server, stream, request, response)`
2. `on_error(error, server, stream, request, response)`

Where:

- `server`: the lua-http server instance (see lua-http docs)
- `stream`: the request stream context (see lua-http docs)
- `request`: the wrapped request object provided by the server (see "[Request object](#Request-object)" below)
- `response`: the wrapped response object provided by the server (see "[Response object](#Response-object)" below)

`on_error` is optional; if `on_reply` raises an error the server will attempt to call `on_error`.

`on_reply` can be defined inside `.config.lua` or returned directly from it — the returned value takes precedence.

Example `.config.lua`:

```lua
-- .config.lua

-- Define an on_reply handler in the configuration. If the server does not obtain a handler
-- from the configuration, it will use this function to handle requests.
function on_reply(_, _, request, response)
    error('~(-:>)')
end

-- Optionally provide an error handler
function on_error(err, _, _, request, response)
    response:status(500)
            :content_type('text/plain')
            :finish("Oops: " .. err)
end

-- If the configuration returns a function, that function will be used as the handler and
-- the above on_reply will not be used.
return function(_, _, _, response)
    response:status(200)
            :content_type('text/plain')
            :finish("Hello world")
end
```

Example packages
---

See the example package under `/examples`, for example:

```bash
./bin/http-server --handler-path ./examples/file_server.srvapp
```

This will start a simple file server using the package in the current directory.

`examples/libraries` also contains several useful helper modules such as a renderer, template engine, and caching; the examples reference these via symbolic links.

API notes
---

### CONFIG object

`CONFIG` is created from command-line arguments at startup and is available throughout the server context.

Fields

- host: server bind address
- port: numeric listening port
- root_dir: working directory
- handler_dir: package directory
- debug: debug mode flag

Methods

- resolve_home: get a path relative to the web root (`CONFIG.root_path`)
- resolve_handler: get a path relative to the handler directory (`CONFIG.handler_dir`)

### Request object

The Request object is a lazy table. Apart from `stream` (the raw request stream), these fields are computed lazily:

- headers: HTTP headers object (see lua-http docs)
- method: request method
- path: URL path
- real_path: path relative to `CONFIG.root` (URL-decoded)
- uri: original request URI
- query_string: query string from the URI (empty string if none)
- query: table of parsed query parameters (key/value pairs)

The Request object can be used to store data during request processing — it is just a lazy table.

### Response object

The Response object provides convenient operations for building responses. Changes to the Response are buffered and applied outbound after the handler completes.

`stream` is the raw request stream. Buffered headers are a lazy property. The following methods are provided:

- `:status(number|string)`: set the HTTP status code, returns the response object
- `:content_type(string)`: set the Content-Type header, returns the response object
- `:finish(nil|string|function|file)`: finish the response

Except for `finish`, other setter methods return the response object to allow chaining. `finish` behavior:

- If `finish(nil)`, the server will write headers and then close the stream without a body.
- If `finish(string)`, the string is written as the body.
- If `finish(function)`, the function will be passed a print-like function used to write to the stream.
- If `finish(file)` (userdata), the file will be streamed to the client.

After calling `finish`, the Response will reject further modifications; attempts to modify it will raise an error.

If the request method is `HEAD`, the server will always close the stream after writing headers and ignore any body writes.

