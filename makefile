ta:
	clear && forge test -vv

t:
	clear && forge test -vv --match-test test_swap_price_up_in
tl:
	clear && forge test -vvvv --match-test test_swap_price_up_in

spell:
	clear && cspell "**/*.*"