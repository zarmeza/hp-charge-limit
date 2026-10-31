#!/usr/bin/env bash
# Unit tests for the pure logic in hp-charge-limit (no hardware needed).
set -uo pipefail
export HPL_LIB_ONLY=1
# shellcheck source=hp-charge-limit
source ./hp-charge-limit

fail=0

check() {
    local desc=$1 got=$2 want=$3
    if [[ $got == "$want" ]]; then
        printf 'ok   %s\n' "$desc"
    else
        printf 'FAIL %s (got %q, want %q)\n' "$desc" "$got" "$want"
        fail=1
    fi
}

check "parse inhibit"        "$(parse_mode '[0x0, 0x4, {0x04, 0xff, 0x00, 0x00}]')" "4"
check "parse auto"           "$(parse_mode '[0x0, 0x4, {0x00, 0xff, 0x00, 0x00}]')" "0"
check "parse 0xff"           "$(parse_mode '[0x0, 0x4, {0xff, 0xff, 0x00, 0x00}]')" "255"
check "parse junk"           "$(parse_mode 'AE_AML_OPERAND_TYPE' || echo ERR)" "ERR"

check "full + auto -> inhibit"      "$(decide 1 100 0)" "inhibit"
check "80 + auto -> inhibit"        "$(decide 1 80 0)"  "inhibit"
check "79 + auto -> auto (deadband)" "$(decide 1 79 0)" "auto"
check "79 + inhibit -> inhibit"     "$(decide 1 79 4)"  "inhibit"
check "75 + inhibit -> auto"        "$(decide 1 75 4)"  "auto"
check "74 + auto -> auto"           "$(decide 1 74 0)"  "auto"
check "unplugged -> auto"           "$(decide 0 80 4)"  "auto"
check "unknown mode -> hold"        "$(decide 1 80 '')" "hold"
check "ship mode -> hold"           "$(decide 1 78 5)"  "hold"

check "mode name 4" "$(mode_name 4)" "inhibit (charge blocked)"
check "mode name 0" "$(mode_name 0)" "auto (charging allowed)"

exit "$fail"
