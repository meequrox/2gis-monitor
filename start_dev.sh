#!/usr/bin/env bash

MODE=${1:-"app"}

case ${MODE} in
app)
	source env.sh

	env \
		ERL_MAX_PORTS=1024 \
		RELEASE_COOKIE="448a225a-1ed4-4ea4-9c82-4d494f1259d5" \
		iex --sname dgm -S mix
	;;
cli)
	iex --sname cli --remsh dgm@"$(uname -n)"
	;;
*)
	echo "Unexpected mode: ${MODE}"
	;;
esac
