LUA HTTP SERVER
===
[Chinese Version](../README.MD)

This is a server derived from the example HTTP server in the lua-http project, with some modifications.

Dependencies:

- [lua-http](https://github.com/daurnimator/lua-http)
- [luafilesystem](https://lunarmodules.github.io/luafilesystem/manual.html) (demo code under `/examples`)

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

The request handling flow of the HTTP server is:

1. Inbound: validate the basic request format
2. Select an appropriate handler
3. Execute the handler logic
4. Outbound: return the headers and body (unless the request method is HEAD)

The logic in `server.lua` covers inbound and outbound processing, while the application logic sits above it and is considered dynamic content.
Without configuration ([Application Suite](#application-suite-and-loading)), it simply returns the request headers.

Global API and Objects
---

Global APIs are provided so that integrated code can conveniently trigger server behavior.

When using dynamic code loading, be careful to isolate the execution environment and protect the server context.

- EventQueue: a reference to the server's cqueue EventLoop; all coroutine operations must be attached to it
- NotifyNextGC: notify the server of the next garbage-collection cycle
- Server: the server object

Application Suite and Loading
---

Without a corresponding suite, the server is only a minimal server that returns request headers.
To provide richer functionality, you must additionally specify the suite path by passing the `--suit` parameter.

A suite is a folder containing `.appmeta`, `.webapp.lua`, or both.
When a suite is used, its path is added to the Lua path.

`.appmeta` is the metadata description file for the suite; essentially a Lua script.
It is used to describe basic information about the application. When `.webapp.lua` exists, this file is optional.

`.webapp.lua` is the suite configuration file and the application entry point. It describes what the server should do when a request arrives.
The `_ENV` of the suite configuration file is an independent table that inherits from the server context.
If the suite uses dynamic code loading, be careful to isolate different `_ENV` tables. When the suite configuration is invoked, the server's `_ENV` is protected.

The lifecycle of a suite follows that of the entire server, so changes made to the suite after startup will not take effect until the server is restarted.
If `.webapp.lua` or `.appmeta` changes, the server must be restarted for the changes to apply.

### Suite Configuration

`.webapp.lua` is the entry point for the application logic. It does not have to be named `.webapp.lua`, but in that case it must be specified in `.appmeta` (see [Writing `.appmeta`](#writing-appmeta)).

Suite configuration is the entry point for HTTP requests. It needs to define an inbound handler and may optionally define an error handler.

When the loader reads a suite, it passes three parameters:
```lua
local app_path, app_cfg, app_meta = ...
```
1. `app_path`: string, the application path pointing to the location of the application code
2. `app_cfg`: table, the application configuration. After options are defined in `.appmeta`, the processed configuration values are placed here. See [Define parameters through options](#define-parameters-through-options)
3. `app_meta`: table, the metadata environment; the content of `.appmeta`, or an empty table if the file does not exist

When an HTTP request enters the server, it calls the code returned by the configuration to handle the request. It uses two methods:

1. `on_reply(server, stream, request, response)`
2. `on_error(error, server, stream, request, response)`

Where:

- `server`: the lua-http server instance; see the lua-http documentation
- `stream`: the current request context object; see the lua-http documentation
- `request`: the server-wrapped request object; see [Request Object](#request-object)
- `response`: the server-wrapped response object; see [Response Object](#response-object)

`on_error` is optional. If `on_reply` raises an error, the server will attempt to call it.
`on_reply` can be configured in `.config.lua` or returned directly; the server prefers the returned value.

```lua
-- .webapp.lua

-- Set directly in the configuration. If the server cannot obtain a handler while processing the
-- configuration, it will use this function to handle requests.
function on_reply(_, _, request, response)
    error('~(-:>)')
end

-- Optionally configure an error handler
function on_error(err, _, _, request, response)
    response:status(500)
            :content_type('text/plain')
            :finish("Oops: " .. err)
end

-- This handler will be used; the on_reply above will not be called
return function(_, _, _, response)
    response:status(200)
            :content_type('text/plain')
            :finish("Hello world")
end
```

### Writing `.appmeta`

In theory, `.appmeta` can contain arbitrary content, but the following global names are used by the server and have fixed formats:

| Name | Description |
|:---:|:---|
| title, name | string, application title, optional |
| description, desc | string, application description, optional |
| options, opts | list, parameter definitions, optional. See below for the format |
| entry | string, specifies the entry code filename, which must be under the suite directory |

#### Define parameters through options

The `options` field in `.appmeta` defines how incoming command-line arguments are processed.
The command-line options defined there must not conflict with options already provided by the server.
```lua
options = {
    -- Each options entry is a collection. Values without keys are registered in the parameter list.
    -- They must start with `-`. In this example, all non-`-` values that follow the option are added to appcfg.
    -- There are two names, which will be written to two different fields.
    { '--webroot', '-d'; };

    -- Define a minimum value; the option is validated when it appears.
    { '--webroot', '-d'; size = { 1 }; };

    -- Define a maximum value; size represents a range.
    { '--webroot', '-d'; size = { 1, 1 }; };

    -- Change the property name to write to; both options are written to the same field, which acts like an alias.
    { '--webroot', '-d'; size = { 1, 1 }; set_prop={'webroot'} };

    -- You can add a default value with the second parameter of set_prop.
    { '--webroot', '-d'; size = { 0, 1 }; set_prop={'webroot', '.'} };

    -- Add a description; it will appear with the option in `--help`.
    { '--webroot', '-d'; size = { 0, 1 }; set_prop={'webroot', '.'};
      desc = 'Web root path.';
    };

    -- Descriptions can span multiple lines.
    { '--webroot', '-d'; size = { 0, 1 }; set_prop={'webroot', '.'};
      desc = { 'Web root path.';
             'Location to serve as a web server'; };
    };
}
```

Notes:
- Repeated definitions cause earlier options to be overwritten by later ones.
- When an option has only one value, it is stored as a string. When it has multiple values, it is converted to a list and added one by one.
- More complex validation logic should be handled by the application code itself.
- It is recommended that application logic normalize the parameter values.

The entire `_ENV` of `appmeta` is passed to the application configuration logic by the loader.

### Example Suites

You can view example suites under `/examples`, for example:

```bash
./bin/http-server --suit ./examples/file_server.srvapp
```

This starts an HTTP file server in the current directory.

`examples/libraries` also contains some useful code, such as renderers, template engines, and caching.
In the examples, these are referenced through symbolic links.

Some API Notes
---

### Request Object

The Request object is a lazy table. In addition to `stream`, which is the underlying request stream, these fields are computed automatically:

- `headers`: the HTTP header object; see the lua-http documentation
- `method`: the request method
- `uri`: the original request URI
- `path`: the URL path (not URL-decoded)
- `path_decoded`: the URL-decoded request path
- `query_string`: the request parameters in the URI, or an empty string if there are none
- `query`: the key-value list of URI parameters
- `content_type`: the request content type, or an empty string if none is present

The Request object can be used to store data during request handling. It is simply a lazy table.

### Response Object

The Response object is used for convenient response operations. Changes to the Response are cached and applied after the handler code completes.

The `stream` is the underlying request stream, and the cached headers form a lazy property. The other members are methods:

- `:status(number|string)`: set the HTTP status code and return the response itself
- `:header(key, value)`: set a custom HTTP response header
- `:content_type(string)`: set the content-type header string and return the response itself
- `:finish(nil|string|function|file)`: end the request

Except for `finish`, all other setter methods return themselves.
They handle different inputs in different ways:
- If it is `nil`, the stream closes after the HTTP headers are written once processing finishes
- If it is a string, it is written directly as the body
- If it is a function, it receives a print function and writes content to the stream
- If it is a file (userdata), it is written to the stream

After calling `finish`, the response rejects further modifications. Calling the modifier methods afterwards triggers an error.
If the HTTP request method is `HEAD`, the stream is closed after the HTTP headers are written, regardless of whether the response is finished, and any body writes are ignored.

Changes
---

Version 2 removed some global variables and tightened the global environment itself:
- The server configuration `CONFIG` no longer appears in the global scope
- When the application configuration is invoked, the global environment is locked
