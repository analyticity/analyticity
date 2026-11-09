#!/bin/sh
# Fills the map tile cache of the project nginx (nginx.conf, /analyticity/tiles/) for the city's bbox,
# so the first visitors do not wait for the slow OSM France tile server. Requests go through the
# public cache URL one at a time with a pause (be gentle to the tile server; no bulk download).
#
#   configure/prefill-tiles.sh                      # Brno bbox, zoom 10–15 (~1 500 tiles)
#   MAX_ZOOM=16 configure/prefill-tiles.sh          # + zoom 16 (~4 100 more)
#   BASE=http://localhost:8098/analyticity/tiles/hot BBOX=16.4,49.1,16.8,49.3 configure/prefill-tiles.sh
#
# Prints a summary of the X-Cache-Status values (HIT = was cached already). Run again to retry
# the tiles that timed out.
set -eu
BASE=${BASE:-https://dexter.fit.vutbr.cz/analyticity/tiles/hot}
BBOX=${BBOX:-16.4,49.1,16.8,49.3}
MIN_ZOOM=${MIN_ZOOM:-10}
MAX_ZOOM=${MAX_ZOOM:-15}
PAUSE=${PAUSE:-0.5}

awk -v bbox="$BBOX" -v z0="$MIN_ZOOM" -v z1="$MAX_ZOOM" 'BEGIN {
    split(bbox, b, ",")
    pi = atan2(0, -1)
    for (z = z0; z <= z1; z++) {
        n = 2 ^ z
        x0 = int((b[1] + 180) / 360 * n); x1 = int((b[3] + 180) / 360 * n)
        y0 = ytile(b[4], n); y1 = ytile(b[2], n)
        for (x = x0; x <= x1; x++) for (y = y0; y <= y1; y++) print z "/" x "/" y
    }
}
function ytile(lat, n,   r) {
    r = lat * pi / 180
    return int((1 - log(sin(r) / cos(r) + 1 / cos(r)) / pi) / 2 * n)
}' > /tmp/prefill-tiles.$$

total=$(wc -l < /tmp/prefill-tiles.$$ | tr -d ' ')
echo "$total tiles, zoom ${MIN_ZOOM}–${MAX_ZOOM}, bbox $BBOX → $BASE"
i=0
while read -r t; do
    i=$((i + 1))
    status=$(curl -s -o /dev/null -D - --max-time 120 "$BASE/$t.png" \
             | awk 'tolower($1) == "x-cache-status:" { s = $2 } /^HTTP/ { c = $2 } END { print (s ? s : "none") "/" c }' \
             | tr -d '\r')
    echo "$status" >> /tmp/prefill-tiles.$$.st
    [ $((i % 100)) -eq 0 ] && echo "$i / $total"
    case "$status" in HIT/*) ;; *) sleep "$PAUSE" ;; esac
done < /tmp/prefill-tiles.$$

sort /tmp/prefill-tiles.$$.st | uniq -c
rm -f /tmp/prefill-tiles.$$ /tmp/prefill-tiles.$$.st
