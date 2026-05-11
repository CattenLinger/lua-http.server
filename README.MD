LUA HTTP SERVER
===

这是一个基于 lua http 示例中的 http server 修改而成的 http server

依赖：
- [lua http](https://github.com/daurnimator/lua-http)
- [lua template - STNet branch](https://github.com/ShinonomeTN/lua-template)

运行：
```
./bin/http-server [options]

./bin/http-server --help
```

主要增加的功能为：
- 通过模板引擎渲染目录而不是直接字符串拼接
- 动态的处理器和页面加载，能直接修改然后查看效果