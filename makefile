ta:
	clear && forge test -vv

t:
	clear && forge test -vv --match-test test_deposit
tl:
	clear && forge test -vvvv --match-test test_deposit

spell:
	clear && cspell "**/*.*"