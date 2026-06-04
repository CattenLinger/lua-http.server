Api server demo
===

An example suit to show how to write an api server.

Demo URLs
---

### [GET] /manifest
call http://localhost:8000/manifest will return luarocks 
manifest from https://luarocks.org/manifest.

Cache will be saved under webroot.

### [POST] /auth
call http://localhost:8000/auth with `username` and `password`
will return the username and hashed password.

Any parameter missing will return 400.

### [GET] /auth
Use any password in basic auth header 'Authorization' will return
username and password. 

Request with header missing will return 403.

### [GET] /shell_call?cmd={cmd_template_name}
Call shell function, returns stdout content