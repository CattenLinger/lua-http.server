LUA HTTP SERVER
===
[Chinese Version](../README.MD)

This is an HTTP server modified from the example HTTP server in lua-http.

Dependencies:

- [lua http](https://github.com/daurnimator/lua-http)
- [luafilesystem](https://lunarmodules.github.io/luafilesystem/manual.html) (demos under `/examples`)

Running:

```
./bin/http-server [options]

./bin/http-server --help
```

Build:
```bash
docker build -t lua-http.server:latest -f docker/Dockerfile .
```

HTTP Server
---

The HTTP server's processing flow:

1. Inbound: validate basic request format
2. Select an appropriate handler
3. Execute handler code
4. Outbound: return headers and content (if not a HEAD request)

`server.lua` handles the inbound and outbound processing, while application logic sits above it and is considered dynamic content.
Without configuration ([Application Suite](#application-suite-and-loading)), it simply outputs request header information.


Global API & Objects
---

Global API allows injected code to conveniently trigger server behaviors.

When using dynamic code loading, pay attention to proper isolation to protect the server context.

- EventQueue: Reference to the server's cqueue EventLoop, all coroutine operations need to be attached here
- NotifyNextGC: Notify the next garbage collection
- Server: Server object
- CONFIG: Server configuration

Application Suite and Loading
---

Without a corresponding suite, the server is just a server that returns request headers.
To have richer functionality, you must specify the suite path with the `--handler-path` parameter.

A suite is a folder containing `.config.lua`. When using a suite, the suite's path is added to the lua path.

`.config.lua` is a description file for the suite, describing how requests should be handled when they arrive.
The _ENV of the suite description file is an independent table that inherits from the server context.
If the suite uses dynamic code loading, be careful to isolate different _ENV tables.

The suite's lifecycle follows the entire server, so suite configuration won't update after startup.
If `.config.lua` is updated, the server needs to be restarted for changes to take effect.

### Important Interfaces

Suite configuration is the entry point for HTTP requests. It must configure an inbound handler, and may optionally configure an error handler.
When an HTTP request arrives, the server calls the code returned by the configuration to handle it. It uses two methods:

1. `on_reply(server, stream, request, response)`
2. `on_error(error, server, stream, request, response)`

Where:

- `server`: lua http server instance, refer to lua-http documentation
- `stream`: Current request context object, refer to lua-http documentation
- `request`: Request object wrapped by the server, see below: [Request Object](#request-object)
- `response`: Response object wrapped by the server, see below: [Response Object](#response-object)

`on_error` is optional. When `on_reply` produces an error, the server will attempt to call it.
`on_reply` can be set in `.config.lua` or returned directly.
The server will prefer the return value.

```lua
-- .config.lua

-- Set directly in the configuration. If the server doesn't get a handler when processing
-- the configuration, it will use this function to handle requests.
function on_reply(_, _, request, response)
    error('~(-:>)')
end

-- Optionally configure an error handler
function on_error(err, _, _, request, response)
    response:status(500)
            :content_type('text/plain')
            :finish("Oops: " .. err)
end

-- This handler will be used, the on_reply above won't be called
return function(_, _, _, response)
    response:status(200)
            :content_type('text/plain')
            :finish("Hello world")
end
```

### Example Suites

You can view example suites in `/examples`, for example:

```bash
./bin/http-server --handler-path ./examples/file_server.srvapp
```

This launches an HTTP file server in the current path.

`examples/libraries` also contains useful code such as renderers, template engines, and caching.
In the examples, these are referenced via symbolic links.

Some API Documentation
---

### CONFIG Object

CONFIG is generated through command-line parameter processing at startup. It is available throughout the context at any time.

### Fields

|             Name | Remarks       |
|---------------:|:-----------|
|           host | Server listening address |
|           port | Number, listening port |
|       root_dir | Working directory    |
|    handler_dir | Suite directory    |
|          debug | Debug mode switch  |

### Methods

|              Name | Remarks                                          |
|----------------:|:--------------------------------------------|
|    resolve_home | Get the path relative to the web root directory (`CONFIG.root_path`)        |
| resolve_handler | Get the path relative to the suite directory (`CONFIG.handler_dir`)         |

### Request Object

The Request object is a lazy table. Besides `stream` which is the request stream itself, these fields are auto-calculated:

- headers: HTTP header object, refer to lua-http documentation
- method: Request method
- path: URL path
- real_path: Path relative to CONFIG.root (URL-decoded)
- uri: Raw request URI
- query_string: Request parameters on the uri, returns empty string if none
- query: Key-value pair list of uri parameters
- content_type: Request content type, returns empty string if none

The Request object can be used to store data during processing. It is just a simple lazy table.

### Response Object

The Response object is used for convenient operations on the response. Changes to Response are cached and executed after the handler code completes.

The `stream` is the request stream itself, and cached headers are a lazy property. The rest are methods:

- `:status(number|string)`: Set HTTP status code, returns response itself
- `:header(key, value)`: Set custom HTTP response header
- `:content_type(string)`: Set content type header string, returns response itself
- `:finish(nil|string|function|file)`: End the request

Except for `finish`, all other setting methods return self.
It handles different inputs with different logic:
- If nil, the stream will close after writing HTTP headers when processing completes;
- If string, it's used directly as the body output;
- If function, a print function will be passed to write content to the stream;
- If file (userdata), it will be written to the stream.

After calling `finish`, the response will refuse modifications. Calling modification methods will trigger an error.
If the HTTP request method is `HEAD`, regardless of whether the response is finished, the stream will be actively closed after writing http headers, and body writes will be ignored.

