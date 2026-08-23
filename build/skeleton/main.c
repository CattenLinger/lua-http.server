#include "lua_headers.h"
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "lhs_codeblocks.h"

/* Copied from lua.c */

static lua_State *globalL = NULL;

static void lstop (lua_State *L, lua_Debug *ar) {
	(void)ar;  /* unused arg. */
	lua_sethook(L, NULL, 0, 0);  /* reset hook */
	luaL_error(L, "interrupted!");
}

static void laction (int i) {
	signal(i, SIG_DFL); /* if another SIGINT happens, terminate process */
	lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

static int msghandler (lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL) {  /* is error object not a string? */
		if (luaL_callmeta(L, 1, "__tostring")     /* does it have a metamethod */
			&& lua_type(L, -1) == LUA_TSTRING)   /* that produces a string? */
			return 1;  /* that is the message */
		
		msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
	}

	luaL_traceback(L, L, msg, 1);  /* append a standard traceback */
    return 1;  /* return the traceback */
}

static int docall (lua_State *L, int narg, int nresult) {
	int base = lua_gettop(L) - narg;  /* function index */

	lua_pushcfunction(L, msghandler);  /* push message handler */
	lua_insert(L, base);  /* put it under function and args */

	globalL = L;  /* to be available to 'laction' */
	signal(SIGINT, laction);  /* set C-signal handler */

	int status = lua_pcall(L, narg, nresult, base);

	signal(SIGINT, SIG_DFL); /* reset C-signal handler */
	lua_remove(L, base);  /* remove message handler from the stack */
	return status;
}

/* Lua Http Server Binary stuff */
static void lhsB_main_create_arg_table (lua_State *L, char **argv, int argc, int script) {
	if (script == argc) script = 0;  /* no script name? */
	int narg = argc - (script + 1);  /* number of positive indices */
	lua_createtable(L, narg, script + 1);
	for (int i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i - script);
	}
	lua_setglobal(L, "arg"); // table was poped
}

// returns `package`
static void lhsB_main_load_codeblocks (lua_State *L) {
	lua_getglobal(L, "package");
	
	lua_newtable(L);
	lhsB_create_runtime_codeblocks(L);
	lua_setfield(L, -2, "vendor");
	lhsB_create_server_codeblocks(L);
	lua_setfield(L, -2, "core");

	lua_setfield(L, -2, "chunks");

	// lhsB_create_clib_preloads(L);
	// lua_setfield(L, -2, "preload");

	lua_remove(L, -1); // pops the table
}

/* Main Entry */
int main(int argc, char **argv) {
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	// Create arge table
	lhsB_main_create_arg_table(L, argv, argc, 0);
	
	// Loads all codes to `package.chunks`
	lhsB_main_load_codeblocks(L);
	
	/*
		cat ./build/bootstrap.lua | ./build/lib/launch ./build/out_lualib.lua --hex-dump
	*/
	static const char bootstrap[] = {
		108,111,99 ,97 ,108,32 ,99 ,104,117,110,107,32 ,61 ,32 ,97 ,115,115,101,114,116,40 ,112,97 ,99 ,107,97 ,103,101,46 ,99 ,
        104,117,110,107,115,46 ,99 ,111,114,101,46 ,105,110,105,116,44 ,32 ,39 ,117,110,101,120,112,101,99 ,116,101,100,32 ,99 ,
        104,117,110,107,32 ,99 ,111,114,101,46 ,105,110,105,116,32 ,110,111,116,32 ,102,111,117,110,100,39 ,41 ,10 ,97 ,115,115,
        101,114,116,40 ,108,111,97 ,100,40 ,99 ,104,117,110,107,44 ,32 ,39 ,99 ,111,114,101,46 ,105,110,105,116,39 ,44 ,32 ,39 ,
        98 ,116,39 ,44 ,32 ,95 ,69 ,78 ,86 ,41 ,41 ,40 ,41 ,
	};
	if (luaL_loadbuffer(L, (const char*)bootstrap, sizeof(bootstrap), "bootstrap") != LUA_OK) {
		fprintf(stderr, "luaL_loadbuffer: %s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

    if (docall(L, 0, 0)) {
		const char *errmsg = lua_tostring(L, 1);
		if (errmsg) fprintf(stderr, "%s\n", errmsg);
		lua_close(L);
		return 1;
	}
	lua_close(L);
	return 0;
}