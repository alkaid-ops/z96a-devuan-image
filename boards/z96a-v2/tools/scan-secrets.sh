#!/bin/bash
# Lightweight secret scan: catches credentials that must not be committed.
#
# This is a fast local gate; CI also runs gitleaks for full-history scanning.
# Known historical values (already in git history) are reported as `legacy`
# instead of failing, because removing them from the working tree does not
# remove them from history — rotation is a manual action (see docs/OPTIMIZATION.md).
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

fail=0
warn=0

report() { printf '%-6s %-45s %s\n' "$1" "$2" "$3"; }
fail_one() { report FAIL "$1" "$2"; fail=$((fail + 1)); }
warn_one() { report WARN "$1" "$2"; warn=$((warn + 1)); }

# Files that may legitimately contain the legacy defaults during migration.
legacy_files="boards/z96a-v2/userscripts/uscripts files/rootfs-overlay/z96a-v2/etc/NetworkManager/system-connections"

scan_pattern() {
    local pattern=$1 label=$2
    while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        local file=${hit%%:*}
        file=${file#./}
        case " $legacy_files " in
            *" $file "*) warn_one "$label (legacy default in $file)" "rotate in docs/OPTIMIZATION.md";;
            *) fail_one "$label" "$hit";;
        esac
    done < <(grep -rInE "$pattern" \
        --exclude-dir=.git --exclude-dir=sources --exclude-dir=output \
        --exclude-dir=.cache --exclude-dir=.ci-cache \
        --exclude='*.patch' --exclude='*.orig' \
        --exclude='SHA256SUMS' --exclude='packages-sources.tsv' . 2>/dev/null)
}

scan_pattern 'root:[0-9]{4,}' 'hardcoded root password'
scan_pattern 'PASSKEY="[^"$][^"]{5,}"' 'hardcoded wifi passkey'
scan_pattern 'ssh-(ed25519|rsa) AAAA[0-9A-Za-z+/]{40,}' 'embedded ssh public key'
scan_pattern '(BEGIN [A-Z ]*PRIVATE KEY)' 'private key material'
scan_pattern 'AKIA[0-9A-Z]{16}' 'aws access key id'
scan_pattern 'gh[pousr]_[0-9A-Za-z]{36,}' 'github token'

# Private keys / credential files must never be tracked.
while IFS= read -r tracked; do
    [ -n "$tracked" ] || continue
    fail_one "tracked credential file" "$tracked"
done < <(git ls-files | grep -E '(^|/)(id_rsa|id_ed25519|credentials\.local|\.env)$' || true)

if [ "$fail" -eq 0 ]; then
    printf '\nSECRET SCAN: PASS (%d legacy warning(s))\n' "$warn"
    exit 0
fi
printf '\nSECRET SCAN: FAIL (%d), %d legacy warning(s)\n' "$fail" "$warn"
exit 1
