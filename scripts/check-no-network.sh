#!/bin/zsh
# Enforces ADR 0009: Farol never opens a network connection.
# 1. No networking APIs in the source of Farol's own code (spikes are excluded: they are not shipped).
# 2. No networking symbols referenced by the compiled FarolCore objects.
# Run from the repository root after `swift build` in FarolCore.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
pattern='import Network|URLSession|NWConnection|NWListener|NWPathMonitor|CFSocket|CFStream|\bsocket\(|\bconnect\(|getaddrinfo|gethostbyname'
if grep -rnE "$pattern" --include='*.swift' FarolCore/Sources Farol; then
    echo "error: networking API found in Farol or FarolCore sources (ADR 0009)"
    fail=1
fi

bin=$(cd FarolCore && swift build --show-bin-path)
# The layout differs between SwiftPM build systems; check whichever compiled form exists.
objects=($bin/FarolCore.o(N) $bin/libFarolCore.a(N) $bin/FarolCore.build/*.o(N))
if (( ${#objects} == 0 )); then
    echo "error: no FarolCore objects found; run 'swift build' in FarolCore first"
    exit 1
fi
symbols='^_(socket|connect|getaddrinfo|gethostbyname|nw_connection_|nw_listener_|CFSocket|CFStreamCreatePairWithSocket)|URLSession'
if nm -u $objects 2>/dev/null | grep -E "$symbols"; then
    echo "error: compiled FarolCore references networking symbols (ADR 0009)"
    fail=1
fi

if (( fail == 0 )); then echo "No networking code found in FarolCore (${#objects} objects checked)."; fi
exit $fail
