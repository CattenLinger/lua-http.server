## Tools
LUAC := luac

## Project structure
SRC_DIR := src

BUILD_PREFIX := build.make
BUILD_LIBDIR := $(BUILD_PREFIX)/lib
BUILD_BINDIR := $(BUILD_PREFIX)/bin

SRCS := $(shell find $(SRC_DIR) -name '*.lua')
OBJS := $(patsubst $(SRC_DIR)/%,$(BUILD_LIBDIR)/%,$(SRCS))
DIRS := $(BUILD_PREFIX) $(BUILD_LIBDIR) $(BUILD_BINDIR)

## Targets

info:
	@echo '================================'
	@echo 'Source Directory  :' $(SRC_DIR)
	@echo 'Build Directories :' $(DIRS)
	@echo 'Source files      :' $(SRCS)
	@echo 'Target outputs    :' $(OBJS)
	@echo '================================'

all: install_deps build app.tar.gz runtime.tar.gz

build: prepare_dir $(OBJS) bin/http-server
	# Copy files
	cp -r ./doc $(BUILD_PREFIX)
	cp README.MD $(BUILD_PREFIX)/doc/README_ZH.MD

clean:
	[ -d $(BUILD_PREIFX) ] && rm -rf $(BUILD_PREFIX)

##
## Modify launcher script
##
bin/http-server: $(BUILD_BINDIR)
	sed 's/$HOME_DIR\/src\//$HOME_DIR\/lib\//g' bin/http-server > $(BUILD_BINDIR)/http-server

##
## Compile source files to lua bytecode
##
$(BUILD_LIBDIR)/%.lua: $(SRC_DIR)/%.lua
	$(LUAC) -o $@ $^

##
## Optional: install dependencies before a build
##
install_deps:
	# Install lua-http
	luarocks install http

runtime.tar.gz: $(BUILD_PREFIX)
	mkdir -p $(BUILD_PREFIX)/lib/lua/

	tar -czvf $(BUILD_PREFIX)/runtime.tar.gz \
		$(shell luarocks config deploy_lua_dir) \
		$(shell luarocks config deploy_lib_dir)

app.tar.gz: build
	tar -czvf $(BUILD_PREFIX)/app.tar.gz -C $(BUILD_PREFIX) \
		bin/ lib/

##
## Prepare directories
##
prepare_dir: $(DIRS)

$(DIRS):
	mkdir -p $@