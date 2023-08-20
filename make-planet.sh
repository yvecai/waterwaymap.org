#!/bin/bash -x
set -o errexit -o nounset
cd "$(dirname "$0")"

source functions.sh

if [ ! -s planet-waterway.osm.pbf ] ; then
	aria2c --seed-time=0 https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf.torrent
	osmium tags-filter --remove-tags --overwrite planet-latest.osm.pbf --output-header osmosis_replication_base_url=https://planet.openstreetmap.org/replication/minute/ -o planet-waterway.osm.pbf waterway
fi

if [ -z "$(osmium fileinfo -g header.option.timestamp planet-waterway.osm.pbf)" ] ; then
	LAST_TIMESTAMP=$(osmium fileinfo --no-progress -e -g data.timestamp.last  planet-waterway.osm.pbf)
	# set the timestamp header
	rm -rf new.osm.pbf
	osmium cat --output-header timestamp=$LAST_TIMESTAMP -o new.osm.pbf planet-waterway.osm.pbf
	mv -v new.osm.pbf planet-waterway.osm.pbf
fi

TMP=$(mktemp -p . "tmp.planet.XXXXXX.osm.pbf")
if [ $(( $(date +%s) - "$(date -d "$(osmium fileinfo -g header.option.timestamp planet-waterway.osm.pbf)" +%s)" )) -gt $(units -t 2days sec) ] ; then
	pyosmium-up-to-date -vv --ignore-osmosis-headers --server https://planet.openstreetmap.org/replication/day/ -s 10000 planet-waterway.osm.pbf
	osmium tags-filter --overwrite --remove-tags planet-waterway.osm.pbf -o "$TMP" w/waterway && mv "$TMP" planet-waterway.osm.pbf
fi
if [ $(( $(date +%s) - "$(date -d "$(osmium fileinfo -g header.option.timestamp planet-waterway.osm.pbf)" +%s)" )) -gt $(units -t 2hours sec) ] ; then
	pyosmium-up-to-date -vv --ignore-osmosis-headers --server https://planet.openstreetmap.org/replication/hour/ -s 10000 planet-waterway.osm.pbf
	osmium tags-filter --overwrite --remove-tags planet-waterway.osm.pbf -o "$TMP" w/waterway && mv "$TMP" planet-waterway.osm.pbf
fi
pyosmium-up-to-date -vv --ignore-osmosis-headers --server https://planet.openstreetmap.org/replication/minute/ -s 10000 planet-waterway.osm.pbf
osmium tags-filter --overwrite --remove-tags planet-waterway.osm.pbf -o "$TMP" w/waterway && mv "$TMP" planet-waterway.osm.pbf
osmium check-refs planet-waterway.osm.pbf || true

osmium check-refs --no-progress --show-ids planet-waterway.osm.pbf |& grep -Po "(?<= in w)\d+$" | uniq | sort -n | uniq > incomplete_ways.txt
if [ "$(wc -l incomplete_ways.txt | cut -f1 -d" ")" -gt 0 ] ; then
	cat incomplete_ways.txt | while read WID ; do
		curl -s -o way_${WID}.osm.xml https://api.openstreetmap.org/api/0.6/way/${WID}/full
	done
	osmium cat --overwrite -o incomplete_ways.osm.pbf way_*.osm.xml
	rm way_*.osm.xml
	rm -rf incomplete_ways2.osm.pbf
	osmium sort -o incomplete_ways2.osm.pbf incomplete_ways.osm.pbf
	mv incomplete_ways2.osm.pbf incomplete_ways.osm.pbf
	echo "" > empty.opl
	rm -rf add-incomplete-ways.osc
	osmium derive-changes empty.opl incomplete_ways.osm.pbf -o add-incomplete-ways.osc
	rm -f empty.opl

	rm -rf new.osm.pbf
	osmium apply-changes --output-header="timestamp!" -o new.osm.pbf planet-waterway.osm.pbf add-incomplete-ways.osc
	mv -v new.osm.pbf planet-waterway.osm.pbf
	rm -fv add-incomplete-ways.osc
	osmium check-refs planet-waterway.osm.pbf || true
fi

# Now do processing

process planet-waterway.osm.pbf planet-waterway-river "-f waterway=river"
rclone copyto ./docs/tiles/planet-waterway-river.pmtiles cloudflare:pmtiles0/2023-04-01/planet-waterway-river.pmtiles  --progress

process planet-waterway.osm.pbf planet-waterway-name-no-group "-f waterway -f name"
rclone copyto ./docs/tiles/planet-waterway-name-no-group.pmtiles cloudflare:pmtiles0/2023-04-01/planet-waterway-name-no-group.pmtiles  --progress

process planet-waterway.osm.pbf planet-waterway-name-group-name "-f waterway -f name -g name"
rclone copyto ./docs/tiles/planet-waterway-name-group-name.pmtiles cloudflare:pmtiles0/2023-04-01/planet-waterway-name-group-name.pmtiles  --progress

wait

exit 0
