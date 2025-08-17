fmt:
	echo "----Formatting----"
	stylua ./lua/run/ --config-path=./stylua.toml

lint:
	echo "----Linting----"
	luacheck lua/ --globals vim

pr-ready: fmt lint
