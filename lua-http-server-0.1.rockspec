package = "lua-http-server"
version = "0.1"
source = {
   url = "https://git.shinonometn.com/cattenlinger/lua-http-file-server.git"
}
description = {
   detailed = "这是一个基于 lua http 示例中的 http server 修改而成的 http server",
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
dependencies = {
   queries = {
      'lua >= 5.2';
      'http >= 0.4';
   }
}
build_dependencies = {
   queries = {}
}
build = {
   type = "builtin",
   modules = {},
   install = {
      bin = {
         "bin/http-server"
      }
   }
}
test_dependencies = {
   queries = {}
}
