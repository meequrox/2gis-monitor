#!/usr/bin/env bash

# For a description, see config/runtime.exs or compose/example.env files.

OUT_DIR="./release/double_gis_monitor"

source env.sh

env \
	ERL_MAX_PORTS=1024 \
	RELEASE_COOKIE="448a225a-1ed4-4ea4-9c82-4d494f1259d5" \
	"$OUT_DIR"/bin/double_gis_monitor start_iex
