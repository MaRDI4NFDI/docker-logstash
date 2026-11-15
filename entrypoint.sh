#!/bin/sh
# Creates or updates the ISM policy that deletes logstash-* indices
# RETENTION_DAYS (default 90) days after their creation, then starts
# Logstash. A changed retention applies to indices created later.
# Logstash installs the index template itself (90-output.conf).
set -u
os=${OPENSEARCH_URL:-http://logging-opensearch:9200}
days=${RETENTION_DAYS:-90}
policy="$os/_plugins/_ism/policies/logstash-retention"
json='Content-Type: application/json'
body=$(cat <<JSON
{
  "policy": {
    "description": "Delete logstash-* indices after $days days",
    "default_state": "hot",
    "states": [
      {
        "name": "hot",
        "actions": [],
        "transitions": [
          { "state_name": "delete", "conditions": { "min_index_age": "${days}d" } }
        ]
      },
      { "name": "delete", "actions": [ { "delete": {} } ], "transitions": [] }
    ],
    "ism_template": [ { "index_patterns": ["logstash-*"], "priority": 100 } ]
  }
}
JSON
)

set_policy() {
	if current=$(curl -sf "$policy"); then
		seq=$(echo "$current" | sed -n 's/.*"_seq_no":\([0-9]*\).*/\1/p')
		term=$(echo "$current" | sed -n 's/.*"_primary_term":\([0-9]*\).*/\1/p')
		curl -sf -XPUT "$policy?if_seq_no=$seq&if_primary_term=$term" -H "$json" -d "$body"
	else
		curl -sf -XPUT "$policy" -H "$json" -d "$body"
	fi
}

# Only when the container starts Logstash, not for other commands
# such as bin/logstash-plugin. Logstash starts anyway after 5 minutes;
# its output keeps retrying.
case "${1:--}" in -*) ;; *) exec /usr/local/bin/docker-entrypoint "$@" ;; esac
tries=0
until curl -sf "$os/_cluster/health?wait_for_status=yellow&timeout=10s" >/dev/null && set_policy; do
	tries=$((tries + 1))
	if [ "$tries" -ge 30 ]; then
		echo "Could not set the retention policy at $os" >&2
		break
	fi
	echo "Waiting for $os"
	sleep 10
done
echo

# (Re)load the MediaWiki dashboards from the image into DASHBOARDS_URL
# in the background, so they never depend on what the volume holds.
# Changes made in the UI to these objects are lost on the next start.
# An empty DASHBOARDS_URL skips this.
dashboards=${DASHBOARDS_URL-http://logstash-dashboards:5601}
import_dashboards() {
	d=$dashboards
	xsrf='osd-xsrf: true'
	for _ in $(seq 60); do
		if curl -sf "$d/api/status" >/dev/null &&
			curl -sf -XPOST "$d/api/saved_objects/_import?overwrite=true" -H "$xsrf" \
				-F file=@/usr/share/logstash/dashboards/mediawiki.ndjson | grep -q '"success":true' &&
			curl -sf -XPOST "$d/api/opensearch-dashboards/settings" -H "$xsrf" -H "$json" \
				-d '{"changes":{"defaultIndex":"logstash","defaultRoute":"/app/dashboards#/view/home"}}' >/dev/null; then
			echo "Loaded the dashboards into $d"
			return
		fi
		sleep 10
	done
	echo "Could not load the dashboards into $d" >&2
}
if [ -n "$dashboards" ]; then
	import_dashboards &
fi

exec /usr/local/bin/docker-entrypoint "$@"
