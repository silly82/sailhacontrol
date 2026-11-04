#!/bin/sh
# Start a new translation from the template.
# Usage: translations/new-language.sh <lang>   e.g. fi, fr, sv, pt_BR
set -e
lang="$1"
case "$lang" in
    ""|*[!A-Za-z_]*) echo "usage: $0 <lang>  (e.g. fi, fr, pt_BR)" >&2; exit 1 ;;
esac
dir="$(dirname "$0")"
out="$dir/harbour-hacontrol-$lang.ts"
if [ -e "$out" ]; then
    echo "$out already exists" >&2
    exit 1
fi
sed "s/<TS version=\"2.1\">/<TS version=\"2.1\" language=\"$lang\">/" \
    "$dir/harbour-hacontrol.ts" > "$out"
echo "Created $out -- translate it with: linguist $out"
