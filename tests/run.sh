#!/usr/bin/env bash
# Tests for the rice manager and the scripts it installs, in tests/test_<area>.sh. Every test gets an
# empty fake $HOME, so nothing on this machine is read or changed; pacman and sudo are replaced by stubs.
#   tests/run.sh           run all tests
#   tests/run.sh NAME...   run the named tests
set -uo pipefail

# The tests import the repo's own python; without this they leave __pycache__ next to it in home/.
export PYTHONDONTWRITEBYTECODE=1

REPO=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
FAILED=()

# shellcheck source=lib.sh
source "$REPO/tests/lib.sh"
for area in "$REPO"/tests/test_*.sh; do
    # shellcheck source=/dev/null
    source "$area"
done

tests=("$@")
[ ${#tests[@]} -gt 0 ] || mapfile -t tests < <(declare -F | awk '{print $3}' | grep '^test_')
for name in "${tests[@]}"; do
    run_test "$name"
done
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "не прошли: ${FAILED[*]}"
    exit 1
fi
echo "все тесты прошли (${#tests[@]})"
