LUA HTTP SERVER
===
[English Version](doc/README_EN.MD)

这是一个基于 lua http 示例中的 http server 修改而成的服务器

依赖：

- [lua http](https://github.com/daurnimator/lua-http)
- [luafilesystem](https://lunarmodules.github.io/luafilesystem/manual.html) (`/exmaples` 下 demo)

运行：

```
./bin/http-server [options]

./bin/http-server --help
```

HTTP 服务器
---

HTTP 服务器的处理流程：

1. 入站，校验基本请求格式
2. 选择合适的处理器
3. 执行处理器代码
4. 出站，返回头与内容（如果不是 HEAD 请求）

server.lua 解决的是入站与出站，而其上就是应用逻辑，属于动态变更的内容。
在没有配置（[套件](#程式套件与加载)）的情况下，它仅会简单输出请求头信息。


全局 API & 对象
---

全局 API 用于让接入的代码可以方便地发起一些服务器行为。

在使用动态代码加载的时候，要注意做好隔离，保护好服务器的上下文。

- EventQueue：服务器的 cqueue EventLoop 引用，所有协程操作都需要挂在这里
- NotifyNextGC：通知下一次 GC
- Server：服务器对象
- CONFIG：服务器配置

程式套件与加载
---

服务器在没有对应的套件时，只是一个会返回请求头的服务器。
如果需要丰富的功能，则必须通过参数 `--handler-path` 额外指定套件路径。

套件是一个包含 `.config.lua` 的文件夹。在使用套件时，套件的路径会被加入到 lua path 中。

`.config.lua` 是对套件的描述文件，用于描述在请求到达时该作何种处理。
套件描述文件的 _ENV 是一个独立的表，继承自服务器的上下文。
如果套件使用了动态代码加载，要注意隔离不同的 _ENV。

套件的生命周期跟随整个服务器，所以套件设置在启动时便不会更新。
如果 `.config.lua` 更新了，需要重启服务器才能生效。

### 重要接口

套件配置是 HTTP 请求的入口，它需要配置一个入站处理器，并可选一个错误处理器。
当 HTTP 请求进入，服务器会调用配置所返回的代码来处理请求。它使用两个方法：

1. `on_reply(server, stream, request, response)`
2. `on_error(error, server, stream, request, response)`

其中：

- `server`：lua http 服务器实例，参照 lua-http 文档
- `stream`：当前请求上下文对象，参照 lua-http 文档
- `request`：服务器包装好的请求对象，见下：[Request 对象](#Request-对象)
- `response`：服务器包装好的回复对象，见下：[Response 对象](#Response-对象)

`on_error` 是可选项， 当 `on_reply` 出现错误时，就会尝试调用它。
`on_reply` 可以通过在 `.config.lua` 中设置，也可以直接返回，
服务器会优先使用返回值。

```lua
-- .config.lua

-- 直接在配置中设置，服务器在处理配置时得不到一个处理器，则会使用这个函数处理
function on_reply(_, _, request, response)
    error('~(-:>)')
end

-- 可选配置一个错误处理器
function on_error(err, _, _, request, response)
    response:status(500)
            :content_type('text/plain')
            :finish("Oops: " .. err)
end

-- 这个处理器将会被使用，上面的 on_reply 不会被调用
return function(_, _, _, response)
    response:status(200)
            :content_type('text/plain')
            :finish("Hello world")
end
```

### 示例套件

可以在 `/examples` 下查看示例套件，例如

```bash
./bin/http-server --handler-path ./examples/file_server.srvapp
```

可在当前路径下启动一个 http 文件服务器。 

`example/libraries` 中也有一些比较有用的代码诸如渲染器、模版引擎以及缓存。
在示例中，以软链的方式引用。

一些 API 说明
---

### CONFIG 对象

CONFIG 在启动的时候通过参数处理生成。它在整个上下文中，可以随时拿出来。

### 字段

|             名称 | 备注      |
|---------------:|:--------|
|           host | 服务器监听地址 |
|           port | 数字，监听端口 |
|       root_dir | 工作目录    |
|    handler_dir | 套件目录    |
|          debug | 调试模式开关  |

### 方法

|              名称 | 备注                                          |
|----------------:|:--------------------------------------------|
|    resolve_home | 得到相对 web 根目录的路径 (`CONFIG.root_path`)        |
| resolve_handler | 得到相对于套件目录的路径 (`CONFIG.handler_dir`)         |

### Request 对象

Request 对象是个 lazy table，除了 stream 是请求流本体外，其中这些字段有自动计算：

- headers：http 头对象，参照 lua http 文档
- method：请求方法
- path：url 路径
- real_path：相对 CONFIG.root 的路径（已 url-decoded）
- uri：原始请求 URI
- query_string：uri 上的请求参数，如果没有则返回空字符串
- query：uri 参数的键值对列表
- content_type： 请求类型，若无则返回空

Request 对象可以用来存储处理过程中的数据，它只是个单纯的 lazy table。

### Response 对象

Response 对象用于对返回作出便捷操作。对 Response 的修改会被暂存，在处理器代码完成后再执行出站。

其中 stream 是请求流本体，暂存的 header 是个 lazy property。其他的是方法：

- `:status(number|string)`：设置 HTTP 状态码，返回 response 本身
- `:header(key, value)`：设置自定义的 HTTP 返回头
- `:content_type(string)`：设置内容类型头字符串，返回 response 本身
- `:finish(nil|string|function|file)`：结束请求

除了 `finish` 以外，其他设置方法均返回自身。
它接受不同的输入会有不同的处理逻辑：
- 如果是 nil，则会在处理结束后，写完 HTTP 头就关闭流；
- 如果是 string，则直接作为 body 输出；
- 如果是 function，则会传入一个打印函数，往流上打印内容；
- 如果是 file（userdata），则会将其写出流。

调用 `finish` 后 `response` 将拒绝修改，修改自身的方法的调用会触发错误。
如果 HTTP 请求方法为 `HEAD`，无论是否结束 response，在写完 http 头后，流都会被主动关闭
，body 的写入会被忽略。

