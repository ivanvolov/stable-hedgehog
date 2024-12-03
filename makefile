ta:
	clear && forge test -vv

t:
	clear && forge test -vv --match-test test_aave_lending_adapter_long
tl:
	clear && forge test -vvvv --match-test test_aave_lending_adapter_long

spell:
	clear && cspell "**/*.*"