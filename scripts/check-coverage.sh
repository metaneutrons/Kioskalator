#!/usr/bin/env bash
# Hard coverage floor for the KioskCore package.
#
# Swift has no --fail-under-lines: neither `swift test` nor `xcodebuild` fails
# below a threshold. A printed percentage is not a floor; the exit code of this
# script is.
#
# Usage: scripts/check-coverage.sh [floor]
set -euo pipefail

floor="${1:-${COVERAGE_FLOOR:-70}}"

# The package lives in Core/; the Xcode project at the root consumes it.
cd "$(dirname "$0")/../Core"

swift test --enable-code-coverage --disable-automatic-resolution
bin="$(swift build --show-bin-path)"

# The first match of a glob is not a selection. Require exactly one bundle, or
# the measurement could pass while describing something else.
bundles=()
while IFS= read -r line; do bundles+=("$line"); done < <(
    find "$bin" -maxdepth 1 -name '*PackageTests.xctest' -print | sort
)
if [ "${#bundles[@]}" -ne 1 ]; then
    printf 'expected exactly one test bundle under %s, found %d\n' \
        "$bin" "${#bundles[@]}" >&2
    printf '  %s\n' "${bundles[@]}" >&2
    exit 1
fi

bundle="${bundles[0]}"
binary="${bundle}/Contents/MacOS/$(basename "$bundle" .xctest)"
test -x "$binary" || { printf 'no test binary at %s\n' "$binary" >&2; exit 1; }

profile="${bin}/codecov/default.profdata"
test -f "$profile" || { printf 'no coverage profile at %s\n' "$profile" >&2; exit 1; }

xcrun llvm-cov export -summary-only -instr-profile "$profile" "$binary" \
    | jq -e --argjson floor "$floor" '
        (.data[0].totals.lines.percent) as $p
        | if $p >= $floor
          then "line coverage \($p | .*100 | round / 100)% >= \($floor)%"
          else error("line coverage \($p | .*100 | round / 100)% below \($floor)%")
          end'
