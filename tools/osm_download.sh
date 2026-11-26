#!/usr/bin/env bash
# Downloads OpenStreetMap data for Bacolod City from the public Overpass API.
# Data © OpenStreetMap contributors, ODbL. Output: data/osm_raw/*.json
# Usage (Git Bash):  bash tools/osm_download.sh
# Already-downloaded files are skipped; delete a file to download it again.
set -e
OUT="data/osm_raw"
mkdir -p "$OUT"
# Public Overpass servers (tried in order; they are sometimes busy)
APIS=("https://overpass-api.de/api/interpreter" "https://overpass.kumi.systems/api/interpreter" "https://overpass.private.coffee/api/interpreter")
# Bounding box: south,west,north,east (downtown Bacolod + surroundings)
BBOX="10.625,122.925,10.705,123.000"

fetch () {  # $1 = file name, $2 = query body
  if [ -s "$OUT/$1" ]; then echo "Have $1 already"; return; fi
  for attempt in 1 2 3; do
    for API in "${APIS[@]}"; do
      echo "Downloading $1 from $API (try $attempt) ..."
      if curl -sS --fail --max-time 150 -A "habal-habal-simulator-map-tool" --data-urlencode "data=[out:json][timeout:240];$2" "$API" -o "$OUT/$1.part"; then
        mv "$OUT/$1.part" "$OUT/$1"
        echo "  $(du -h "$OUT/$1" | cut -f1)"
        return
      fi
      sleep 5
    done
  done
  echo "FAILED to download $1"
  exit 1
}

fetch roads.json "(way[\"highway\"]($BBOX););out body geom;"
fetch buildings.json "(way[\"building\"]($BBOX););out body geom;"
fetch areas.json "(way[\"leisure\"~\"park|pitch|stadium\"]($BBOX);way[\"landuse\"~\"grass|recreation_ground|cemetery\"]($BBOX);way[\"natural\"~\"water|beach|sand\"]($BBOX);way[\"waterway\"~\"river|canal\"]($BBOX););out body geom;"
fetch coast.json "(way[\"natural\"=\"coastline\"]($BBOX););out body geom;"
fetch pois.json "(node[\"amenity\"]($BBOX);way[\"amenity\"~\"fuel|hospital|clinic|place_of_worship|marketplace|school|college|university|townhall\"]($BBOX);node[\"shop\"]($BBOX);way[\"shop\"~\"mall|supermarket|department_store\"]($BBOX);node[\"tourism\"]($BBOX);node[\"leisure\"]($BBOX););out center tags;"
fetch boundary.json "(relation[\"boundary\"=\"administrative\"][\"name\"~\"Bacolod\"];);out geom;"
echo "Done."
