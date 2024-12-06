test_all:
	clear && forge test -vv

t:
	clear && forge test -vv --match-test test_swap_price_down_in
tl:
	clear && forge test -vvvv --match-test test_swap_price_down_in

spell:
	clear && cspell "**/*.*"