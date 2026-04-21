#!/bin/sh
# Burble Bolt — send a magic incoming-call packet to an IP or domain.
#
# Usage:
#   bin/burble bolt 192.168.1.100
#   bin/burble bolt 192.168.1.100/aa:bb:cc:dd:ee:ff
#   bin/burble bolt fe80::1
#   bin/burble bolt user@example.com
#   bin/burble bolt --broadcast
#   bin/burble bolt --name "Alice" 192.168.1.100
#
# Bolt travels on UDP port 7373 (Burble native) and port 9 (WoL compat).
# NAPTR/SRV DNS lookup is used when a domain is given instead of an IP.
#
# Does NOT require the Burble server to be running — runs as a standalone eval.

set -eu

# shellcheck disable=SC1091
. "${RELEASE_ROOT}/releases/${RELEASE_VSN}/env.sh"

exec "${RELEASE_ROOT}/bin/burble" eval "Burble.Bolt.cli_main(System.argv())" -- "$@"
