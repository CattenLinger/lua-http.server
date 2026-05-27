package = "lua-http-server"
version = "0.1-0"
source = {
    url = "git+https://git.shinonometn.com/cattenlinger/lua-http-file-server.git";
    branch = 'master';
}
description = {
    detailed = "这是一个基于 lua http 示例中的 http server 修改而成的 http server",
    homepage = "https://github.com/CattenLinger/lua-http.server",
    license = "*** please specify a license ***"
}
dependencies = {
    'lua >= 5.2';
    'http >= 0.4';
}
build = {
    type = "builtin",
    modules = {
    },
    install = {
        bin = {
            ["http-server"] = "lua/server.lua";
        };
        lua = {
            --[[ Utils ]]--
            'lua/utils.lua'; 'lua/config.lua'; 'lua/log.lua';
            --[[ Server COM ]]--
            'lua/dispatcher.lua'; 'lua/request.lua'; 'lua/response.lua';
        };
    };
    copy_directories = {
        'doc';
    };
}