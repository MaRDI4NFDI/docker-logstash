# docker-logstash

Logstash image for the MaRDI portal's MediaWiki logs:
upstream [logstash-oss](https://www.elastic.co/docs/reference/logstash)
plus the [logstash-output-opensearch](https://github.com/opensearch-project/logstash-output-opensearch)
plugin. Wikimedia runs the same combination; they install the plugin as
a Debian package on their logging hosts
([Wikitech: Logstash](https://wikitech.wikimedia.org/wiki/Logstash#Plugins)).

The image has no pipeline of its own. The pipeline, OpenSearch and
OpenSearch Dashboards are deployed by the `logstash` chart in
[portal-k8s](https://github.com/MaRDI4NFDI/portal-k8s/tree/main/charts/logstash),
which also documents how to search the logs.

## Image

`ghcr.io/mardi4nfdi/logstash`, built by GitHub Actions:

| Event | Tags |
|---|---|
| push to `main` | Logstash version (e.g. `8.19.25`), `latest`, `sha-<commit>` |
| pull request | built, not pushed |

CI reads the Logstash version from the `FROM` line. A rebuild with the
same Logstash, e.g. for a new plugin, moves that tag to a new digest.
Like docker-wikibase, each push to `main` then opens a pull request in
portal-k8s (branch `update/logstash`) that deploys the new image as
`<version>@<digest>`. Merging it deploys the image.

## Updating

- Logstash: change the `FROM` tag. Dependabot proposes new ones.
- Plugin: change `--version` in the Dockerfile by hand (Dependabot
  cannot see it); see its
  [releases](https://rubygems.org/gems/logstash-output-opensearch/versions).

Check locally that the image builds and the plugin is present:

```bash
docker build -t logstash:test . && docker run --rm logstash:test bin/logstash-plugin list --verbose logstash-output-opensearch
```

The plugin install needs more than JRuby's default 1 GB heap, hence
`JRUBY_OPTS` in the Dockerfile.
