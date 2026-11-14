#!/bin/sh
# Copies Wikimedia's Logstash template and filters, unchanged, from
# operations/puppet (modules/profile/files/logstash). The image adapts
# the template with ../template.jq, not here. Usage: ./update.sh [commit]
# Without a commit it takes the current head of the production branch.
set -eu
cd "$(dirname "$0")"
repo=wikimedia/operations-puppet
commit=${1:-$(curl -fsS "https://api.github.com/repos/$repo/commits/production" |
	sed -n 's/^  "sha": "\([0-9a-f]*\)".*/\1/p')}
dir=modules/profile/files/logstash
base="https://raw.githubusercontent.com/$repo/$commit/$dir"
# SOURCE names the commit and each file by its SWHID, the identifier
# Software Heritage archives code under. A file's SWHID is its git
# blob hash, so it is computed locally.
origin="https://github.com/$repo"
rev="swh:1:rev:$commit"
echo "$rev;origin=$origin" > SOURCE
for f in \
	templates/logstash_7.0-1.json \
	filters/50-filter_mediawiki.conf \
	filters/70-filter_add_normalized_message.conf \
	filters/70-filter_normalize_log_levels.conf \
	filters/75-filter_throttle.conf \
	filters/80-filter_truncate.conf
do
	curl -fsS "$base/$f" -o "$(basename "$f")"
	echo "swh:1:cnt:$(git hash-object "$(basename "$f")");origin=$origin;anchor=$rev;path=/$dir/$f" >> SOURCE
done
echo "Updated to $repo $commit"
