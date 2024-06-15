.PHONY: build-release start-release build start cli clean

MIX=mix
MIX_FILES=mix.exs mix.lock

SOURCES=config lib priv
BUILD_ARTIFACTS=_build deps
START_ARTIFACTS=log

RELEASE_DIR=release
RELEASE_PATH=$(RELEASE_DIR)/double_gis_monitor

ERL_MAX_PORTS=1024
RELEASE_COOKIE=448a225a-1ed4-4ea4-9c82-4d494f1259d5
NODENAME=dgm
HOSTNAME=$(shell uname -n)

include env

##
## DEVELOPMENT
##

build: $(MIX_FILES) $(SOURCES)
	$(MIX) deps.get
	$(MIX) deps.compile
	$(MIX) compile

start: $(BUILD_ARTIFACTS)
	DGM_TIMEZONE=$(DGM_TIMEZONE) \
	DGM_CITY=$(DGM_CITY) \
	DGM_TG_TOKEN=$(DGM_TG_TOKEN) \
	DGM_TG_CHANNEL=$(DGM_TG_CHANNEL) \
	iex --sname $(NODENAME) -S mix

cli: $(BUILD_ARTIFACTS)
	iex --sname cli --remsh $(NODENAME)@$(HOSTNAME)

##
## DEVELOPMENT
##

build-release: $(MIX_FILES) $(SOURCES)
	MIX_ENV=prod $(MIX) deps.get --only $(MIX_ENV)
	MIX_ENV=prod $(MIX) release --path $(RELEASE_PATH) --overwrite

start-release: $(RELEASE_PATH)
	DGM_TIMEZONE=$(DGM_TIMEZONE) \
	DGM_CITY=$(DGM_CITY) \
	DGM_TG_TOKEN=$(DGM_TG_TOKEN) \
	DGM_TG_CHANNEL=$(DGM_TG_CHANNEL) \
	$(RELEASE_PATH)/bin/double_gis_monitor start_iex

##
## MISC
##

clean:
	$(RM) -rf $(BUILD_ARTIFACTS) $(START_ARTIFACTS) $(RELEASE_DIR)
