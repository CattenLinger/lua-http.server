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

构建：
```bash
## Debian
docker build -t lua-http.server:latest -f docker/Dockerfile .

## Alpine
docker build -t lua-http.server:alpine-latest -f docker/Dockerfile.alpine .

## Debian（二进制打包，但成品依旧需要 liblua）
docker build -t lua-http.server:latest-bin -f docker/Dockerfile.binary.debian
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

程式套件与加载
---

服务器在没有对应的套件时，只是一个会返回请求头的服务器。
如果需要丰富的功能，则必须通过参数 `--suit` 额外指定套件路径。

套件是一个包含 `.appmeta`、`.webapp.lua`，或者两者的文件夹。
在使用套件时，套件的路径会被加入到 lua path 中。

`.appmeta` 是对套件的描述元数据文件，本质是一个 lua 脚本。
用于描述应用的一些基础信息。当 `.webapp.lua` 存在时，此文件可选。

`.webapp.lua` 是套件的配置文件，也是整个应用的代码入口，用于描述在请求到达时该作何种处理。
套件配置文件的 _ENV 是一个独立的表，继承自服务器的上下文。
如果套件使用了动态代码加载，要注意隔离不同的 _ENV。在套件配置被调用时，服务器的 _ENV 会被保护。

套件的生命周期跟随整个服务器，所以套件设置在启动后便不会更新。
如果 `.webapp.lua`/`.appmeta` 更新了，需要重启服务器才能生效。

### 套件配置
`.webapp.lua` 是应用逻辑的入口。它可以不是 `.webapp.lua`，但这样的话，需要在 `.appmeta` 中指定（见下[`.appmeta` 编写](#`.appmeta`+编写)）

套件配置是 HTTP 请求的入口，它需要配置一个入站处理器，并可选一个错误处理器。

加载时，加载器传入三个参数：
```lua
local app_path, app_cfg, app_meta = ...
```
1. app_path：string，应用路径，指向应用代码所在位置
2. app_cfg：table，应用配置，当在 `.appmeta` 中定义了 `options` 后，处理好的配置项将放在这里。见：[通过 options 定义入参](#通过+options+定义入参)
3. app_meta：table，元数据环境，`.appmeta` 的内容，如果没有此文件，则为空。

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
-- .webapp.lua

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

### `.appmeta` 编写

理论上 `.appmeta` 可以是任意内容，但以下全局名称会被服务器使用。
它们大小写不敏感，且有固定的格式：

| 名称 | 说明 |
|:---:|:---|
| title, name | string，应用标题，可选 |
| description, desc | string，应用描述，可选 |
| options, opts | list，参数定义，可选。格式见下 |
| entry | string，指定入口代码文件名，需在套件目录下。 |

#### 通过 options 定义入参

`.appmeta` 的 `options` 用以指示如何处理传入的命令行参数。
需要其中定义的命令行选项不能与服务器已经有的选项重合。
```lua
options = {
    -- 每个 options 是一个集合，其中的无 key 的值会被注册到参数列表中。
    -- 必须以 `-` 开头。 这个例子里，选项后跟随的非 `-` 开头的值会全部加进 appcfg 中
    -- 这里有两个名字，会被分别写到两个不同的字段里
    { '--webroot', '-d'; };
    
    -- 定义一个最小值，在选项出现时会校验
    { '--webroot', '-d'; size = { 1 }; };
    
    -- 定义一个最大值，size 代表一个 range
    { '--webroot', '-d'; size = { 1, 1 }; };
    
    -- 更改写入的属性名，两个选项都会被写进同一个字段，相当于别名。
    { '--webroot', '-d'; size = { 1, 1 }; set_prop={'webroot'} };
    
    -- 可以通过 set_prop 的第二个参数增加一个默认值。
    { '--webroot', '-d'; size = { 0, 1 }; set_prop={'webroot', '.'} };

    -- 增加一个描述，将会在 `--help` 出现时跟着选项一起输出
    { '--webroot', '-d'; size = { 0, 1 }; set_prop={'webroot', '.'};
      desc = 'Web root path.';
    };

    -- 描述可以是多行的
    { '--webroot', '-d'; size = { 0, 1 }; set_prop={'webroot', '.'};
      desc = { 'Web root path.';
             'Location to serve as a web server'; }; 
    };
}
```

注意：
- 重复定义会导致先前的选项被后来的选项覆盖。
- 当选项只有一个时，值是字符串本身。当值有多个时，会转换为列表逐一加入。
- 更复杂的校验逻辑，应由具体的应用内代码决定。
- 建议应用逻辑对参数内容作规整化。

appmeta 的整个 `_ENV` 本身会被加载器传入应用配置逻辑中。

### 示例套件

可以在 `/examples` 下查看示例套件，例如

```bash
./bin/http-server --suit ./examples/file_server.srvapp
```

可在当前路径下启动一个 http 文件服务器。 

`example/libraries` 中也有一些比较有用的代码诸如渲染器、模版引擎以及缓存。
在示例中，以软链的方式引用。

一些 API 说明
---

### Request 对象

Request 对象是个 lazy table，除了 stream 是请求流本体外，其中这些字段有自动计算：

- headers：http 头对象，参照 lua http 文档
- method：请求方法
- uri：原始请求 URI
- path：url 路径（未 url-decode）
- path_decoded：已 url-decoded 的请求路径
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

变动
---

v2 版删除了一些全局变量，并对全局本身作出了限制：
- 服务器配置 `CONFIG` 不再出现在全局
- 在调用应用的配置时，全局会被上锁
- lua 默认的 package 被替换成一个永远返回空列表的表
- lua 默认的 require 被替换成服务器定制的 require