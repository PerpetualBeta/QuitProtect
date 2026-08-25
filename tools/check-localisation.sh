#!/bin/bash
#
# Build-time guard for the gesture timing catalog.
#
# QuitGestureTiming is the single source of truth for the timing values Settings
# offers, and each option names the Localizable.strings key it renders under. Nothing
# in the type system ties the two together: add an option and forget the string, and
# the picker quietly falls back to the derived label ("1.25s") in every language. Add
# a string and remove the option, and translators keep maintaining a dead entry.
#
# So check both directions, in every .lproj, and fail the build on either.

set -euo pipefail

cd "$(dirname "$0")/.."

CATALOG="Sources/Core/QuitGestureTiming.swift"
RESOURCES="Resources"

if [[ ! -f $CATALOG ]]; then
    echo "check-localisation: cannot find $CATALOG" >&2
    exit 1
fi

catalog_keys=$(sed -n 's/.*localizationKey: "\([^"]*\)".*/\1/p' "$CATALOG" | sort -u)

if [[ -z $catalog_keys ]]; then
    # A rename or a refactor that drops the `localizationKey:` label would otherwise make
    # this script pass by checking nothing at all.
    echo "check-localisation: no localizationKey entries found in $CATALOG" >&2
    exit 1
fi

catalog_count=$(printf '%s\n' "$catalog_keys" | wc -l | tr -d ' ')
lproj_count=0
failed=0

for lproj in "$RESOURCES"/*.lproj; do
    strings_file="$lproj/Localizable.strings"
    [[ -f $strings_file ]] || continue
    lproj_count=$((lproj_count + 1))

    strings_keys=$(sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' "$strings_file" | sort -u)

    missing=$(comm -23 <(printf '%s\n' "$catalog_keys") <(printf '%s\n' "$strings_keys"))
    if [[ -n $missing ]]; then
        failed=1
        while read -r key; do
            echo "check-localisation: $strings_file has no entry for catalog key \"$key\"" >&2
        done <<<"$missing"
    fi

    # Only duration keys, because the rest of Localizable.strings is not this catalog's
    # business.
    orphans=$(printf '%s\n' "$strings_keys" \
        | sed -n '/^duration\./p' \
        | comm -23 - <(printf '%s\n' "$catalog_keys"))
    if [[ -n $orphans ]]; then
        failed=1
        while read -r key; do
            echo "check-localisation: $strings_file defines \"$key\", which no timing option uses" >&2
        done <<<"$orphans"
    fi
done

if [[ $lproj_count -eq 0 ]]; then
    echo "check-localisation: no Localizable.strings found under $RESOURCES" >&2
    exit 1
fi

if [[ $failed -ne 0 ]]; then
    exit 1
fi

echo "check-localisation: $catalog_count timing keys present in $lproj_count localisations"
