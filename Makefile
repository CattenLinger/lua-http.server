## Tools
LUAC := luac

## Project structure
SRC_DIR := lua

LUA_INCDIR :=/opt/homebrew/include/lua5.4/
LUA_LIBDIR :=/opt/homebrew/lib
LUA_LIBNAME :=liblua.a

BUILD_PREFIX := ./build.make
BUILD_SRC    := ./build
BUILD_LUADIR := $(BUILD_PREFIX)/lua
BUILD_BINDIR := $(BUILD_PREFIX)/bin
BUILD_LAUNCH := $(BUILD_SRC)/lib/launch

SRCS := $(shell find $(SRC_DIR) -name '*.lua')
SRCS_SUBDIRS := $(shell find $(SRC_DIR) -type d) # use `-type d` here for busybox compability
OBJS := $(patsubst $(SRC_DIR)/%,$(BUILD_LUADIR)/%,$(SRCS))
OBJS_SUBDIRS := $(patsubst $(SRC_DIR)/%,$(BUILD_LUADIR)/%,$(SRCS_SUBDIRS))

DIRS := $(BUILD_PREFIX) $(BUILD_LUADIR) $(BUILD_BINDIR) ${OBJS_SUBDIRS}

LUAROCKS_LUA_DIR :=$(shell luarocks config deploy_lua_dir)
LUAROCKS_LIB_DIR :=$(shell luarocks config deploy_lib_dir)

LHS_PROCEDURE_SERVER_MOD  := lhsB_create_server_codeblocks
LHS_PROCEDURE_RUNTIME_MOD := lhsB_create_runtime_codeblocks
# LHS_PROCEDURE_C_MOD       := lhsB_create_clib_preloads

##
## Utility Targets
##

## Compile source files to lua bytecode
$(BUILD_LUADIR)/%.lua: $(SRC_DIR)/%.lua
	$(LUAC) -o $@ $^

## Prepare directories
$(DIRS):
	mkdir -p $@

##
## Main Targets
##
.PHONY: info
info:
	@echo '================================'
	@echo 'Source Directory  :' $(SRC_DIR)
	@echo 'Build Directories :' $(DIRS)
	@echo 'Source files      :' $(SRCS)
	@echo 'Target outputs    :' $(OBJS)
	@echo ''
	@echo 'LuaRocks Info'
	@echo 'deploy_lua_dir: ' $(LUAROCKS_LUA_DIR)
	@echo 'deploy_lib_dir: ' $(LUAROCKS_LIB_DIR)
	@echo '================================'
	@echo 'make build: build all materials'
	@echo 'make clean: clean up build folder'

.PHONY: all
all: build $(BUILD_PREFIX)/app.tar.gz $(BUILD_PREFIX)/runtime.tar.gz

.PHONY: build
build: $(DIRS) $(OBJS) $(BUILD_BINDIR)/http-server
	# Copy files
	cp -r ./doc $(BUILD_PREFIX)
	cp README.MD $(BUILD_PREFIX)/doc/README_ZH.MD

.PHONY: clean
clean:
	[ -d $(BUILD_PREIFX) ] && rm -rf $(BUILD_PREFIX)

##
## Targets for single binary
##

## Collect Server Module List
$(BUILD_PREFIX)/server.modlist: $(DIRS) $(OBJS)
	find $(BUILD_LUADIR) -name '*.lua' | sed "s|$(BUILD_LUADIR)/||g" > $@
$(BUILD_PREFIX)/server_mods.c.part: $(BUILD_PREFIX)/server.modlist
	# Server codes already compiled, no -c needed 
	cat $^ | $(BUILD_LAUNCH) $(BUILD_SRC)/out_lualib.lua \
		-- $(BUILD_LUADIR)/ -m $(LHS_PROCEDURE_SERVER_MOD) > $@

## Collect Runtime Module List
$(BUILD_PREFIX)/runtime.path.modlist: $(DIRS)
	find $(LUAROCKS_LUA_DIR) -name '*.lua' | sed "s|$(LUAROCKS_LUA_DIR)/||g" > $@
$(BUILD_PREFIX)/runtime_mods.c.part: $(BUILD_PREFIX)/runtime.path.modlist
	cat $^ | $(BUILD_LAUNCH) $(BUILD_SRC)/out_lualib.lua \
		-- $(LUAROCKS_LUA_DIR)/ -c $(LUAC) -m $(LHS_PROCEDURE_RUNTIME_MOD) > $@

## Collect Runtime C Module List
# $(BUILD_PREFIX)/runtime.cpath.modlist: $(DIRS)
# 	find $(LUAROCKS_LIB_DIR) -name '*.so' | sed "s|$(LUAROCKS_LIB_DIR)/||g" > $@
# $(BUILD_PREFIX)/runtime_clib.c.part: $(BUILD_PREFIX)/runtime.cpath.modlist
# 	cat $^ | $(BUILD_LAUNCH) $(BUILD_SRC)/out_clib.lua -- $(LUAROCKS_LIB_DIR)/ -m $(LHS_PROCEDURE_C_MOD) > $@

## compile C codes
$(BUILD_PREFIX)/lhs_codeblocks.c : $(BUILD_PREFIX)/runtime_mods.c.part $(BUILD_PREFIX)/server_mods.c.part
	printf '#include "lhs_codeblocks.h"\n' > $(BUILD_PREFIX)/lhs_codeblocks.c
	cat $^ >> $(BUILD_PREFIX)/lhs_codeblocks.c

## assembly C codes
$(BUILD_PREFIX)/lhs_codeblocks.o : $(BUILD_PREFIX)/lhs_codeblocks.c
	gcc -c -o $@ -Wall -O2 \
		-I$(LUA_INCDIR) \
		-I$(BUILD_SRC)/skeleton/ \
		$^

# NOTE: gcc flag order matters
#
# Also: No static embed (-static, or -ldl -lm) here because external c modules
# are depends on liblua.so, embedding lua runtime is meaningless
$(BUILD_PREFIX)/lhsrv : $(BUILD_PREFIX)/lhs_codeblocks.o
	cp -v $(BUILD_SRC)/skeleton/* $(BUILD_PREFIX)/
	gcc -o $@ -Wall -O2 \
		-I$(LUA_INCDIR) \
		$^ $(BUILD_PREFIX)/main.c \
		-l$(LUA_LIBNAME)

# Copy runtime libraries
# NOTE: The luarocks' lib directory contains usually only .so files.
$(BUILD_PREFIX)/lib: $(BUILD_PREFIX)
	mkdir -p $@
	cp -r $(LUAROCKS_LIB_DIR)/. $@

# Pack all binaries
$(BUILD_PREFIX)/lhsrv.tar.gz : $(BUILD_PREFIX)/lhsrv $(BUILD_PREFIX)/lib
	tar -czvf $@ -C $(BUILD_PREFIX) lhsrv lib/

##
## Targets for docker image build
##
.PHONY: install_deps
install_deps:
	# Install lua-http
	luarocks install http

## Modify launcher script
$(BUILD_BINDIR)/http-server: $(BUILD_BINDIR)
	cat bin/http-server > $(BUILD_BINDIR)/http-server

# This will pack the luarock's deploy path
$(BUILD_PREFIX)/runtime.tar.gz: $(BUILD_PREFIX)/lib
	tar -czvf $@ \
		$(LUAROCKS_LUA_DIR) \
		$(LUAROCKS_LIB_DIR)

# This will pack all the lua codes and launcher scripts needed
$(BUILD_PREFIX)/app.tar.gz: build
	tar -czvf $@ -C $(BUILD_PREFIX) \
		bin/ lua/