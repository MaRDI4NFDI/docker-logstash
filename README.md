# docker-logstash

Logstash for the MaRDI portal's MediaWiki logs, with the pipeline
Wikimedia uses: upstream
[logstash-oss](https://www.elastic.co/docs/reference/logstash), the
[logstash-output-opensearch](https://github.com/opensearch-project/logstash-output-opensearch)
plugin, and Wikimedia's MediaWiki filters and index template.
Wikimedia installs the plugin as a Debian package on its logging hosts
([Wikitech: Logstash](https://wikitech.wikimedia.org/wiki/Logstash#Plugins)).

portal-k8s runs the image as the `logstash` release (chart
`stateless-service`), next to `logstash-dashboards` and
`logging-opensearch`. Its
[README](https://github.com/MaRDI4NFDI/portal-k8s/tree/main/apps/base/logstash/README.md)
explains how to search the logs and look after the stack.

```text
MediaWiki ──UDP 11514──► logstash ──► OpenSearch (OPENSEARCH_URL)
                                      index logstash-<type>-YYYY.MM.DD
```

## What the image does

- `pipeline/00-input.conf` takes one Logstash JSON record per UDP
  datagram on port 11514.
- `pipeline/10-filter_mardi.conf` sets a default `type` and moves a
  string `exception` to `exception_message`.
- Wikimedia's five filters from `wmf/` tag MediaWiki records, drop the
  `api` channel, add a checksum to exceptions, add
  `normalized_message`, normalize levels, throttle a message repeated
  more than 5000 times in 5 minutes, and truncate over-long fields.
- `pipeline/90-output.conf` writes to `OPENSEARCH_URL` (default
  `http://logging-opensearch:9200`) and installs the index template on
  startup.
- `entrypoint.sh` creates or updates the ISM policy
  `logstash-retention` before Logstash starts. It deletes an index
  `RETENTION_DAYS` (default 90) days after its creation. A changed
  value applies to indices created afterwards.

Logstash keeps no state: its queue is in memory, and all records live
in OpenSearch.

### Lost UDP records

UDP has no flow control: when Logstash reads too slowly, the kernel
drops records once the socket buffer is full. On the cluster nodes
`net.core.rmem_max` is 212992 bytes. A pod cannot raise it: the
kubelet rejects the sysctl (`SysctlForbidden`), and `/proc/sys` is
read-only in the container. So the input asks for exactly that much
(`UDP_RECEIVE_BUFFER_BYTES`), which the kernel doubles to 416 KiB.
Asking for more only adds a warning; asking for nothing leaves the
default of 208 KiB. Beyond that, the input queues up to
`UDP_QUEUE_SIZE` (default 20000) records in memory.

Measured locally with that 416 KiB buffer and 1 KB records, sent for
10 seconds at an even rate:

| Rate | Queue 2000 | Queue 20000 | 8 MiB buffer |
|---|---|---|---|
| 5000/s | none lost | | |
| 10000/s | 819 of 100000 lost | 85 lost | none lost |

The kernel counts dropped records as `RcvbufErrors` in the pod:

```bash
kubectl -n production exec deploy/logstash -- grep '^Udp:' /proc/net/snmp
```

## Wikimedia's template and filters

`wmf/` holds unchanged copies of Wikimedia's index template and five
Logstash filters from
[operations/puppet](https://github.com/wikimedia/operations-puppet/tree/production/modules/profile/files/logstash)
(Apache-2.0). `wmf/SOURCE` names the commit and each file by its
[SWHID](https://www.swhid.org/), the identifier of the
[Software Heritage archive](https://archive.softwareheritage.org/).

`template.jq` adapts the template for a single node at build time: no
SSD-only allocation, no replicas, and `exception` mapped as an object.
Without that mapping, a string `exception` arriving first would make
the day's index reject all real exception records. Wikimedia's routing
and index validation filters are not used; they rely on index names
that Wikimedia's Puppet generates.

A weekly workflow (`update-wmf.yml`) runs `wmf/update.sh` and opens a
pull request when one of the copied files changed. To update by hand,
run `wmf/update.sh` (optionally with a commit), then review the diff.

## Image and releases

`ghcr.io/mardi4nfdi/logstash`, built by GitHub Actions:

| Event | Tags |
|---|---|
| push to `main` | `latest`, `sha-<commit>` |
| release tag `vX.Y.Z` | `X.Y.Z`, `sha-<commit>` |
| pull request | built, not pushed |

The version is our own: it counts changes to the image, whatever they
are (Logstash, plugin, pipeline or Wikimedia's files). Bump the major
version for changes that need action in portal-k8s, the minor version
for new behaviour, the patch version for the rest.

Like docker-wikibase's production releases, a release tag opens a pull
request in portal-k8s (branch `update/logstash`) that deploys
`X.Y.Z@<digest>`. Merging into `main` alone deploys nothing.

To release, create the tag with a GitHub release, e.g.:

```bash
gh release create v1.0.1 --repo MaRDI4NFDI/docker-logstash --generate-notes
```

A tag created by a workflow with `GITHUB_TOKEN` would not start the
build, so there is no release workflow.

## Updating

- Logstash: change the `FROM` tag. Dependabot proposes new ones;
  release after merging.
- Plugin: change `--version` in the Dockerfile by hand (Dependabot
  cannot see it); see its
  [releases](https://rubygems.org/gems/logstash-output-opensearch/versions).

The plugin install needs more than JRuby's default 1 GB heap, hence
`JRUBY_OPTS` in the Dockerfile.

## Trying it locally

Run OpenSearch 2.19 as `logging-opensearch` (or set `OPENSEARCH_URL`)
and start the image with `11514/udp` published, e.g. with docker
compose. Then send a record:

```bash
echo '{"type":"mediawiki","channel":"test","level":"ERROR","message":"hello"}' | nc -u -w1 127.0.0.1 11514
```

To have a local MediaWiki send its logs, set `$wgMWLoggerDefaultSpi`
to a `MonologSpi` with a `SocketHandler` for `udp://127.0.0.1:11514`
and MediaWiki's `LogstashFormatter`, near the top of LocalSettings.php.
