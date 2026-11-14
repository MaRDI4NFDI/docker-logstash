FROM alpine:3.22 AS template
RUN apk add --no-cache jq
COPY wmf/logstash_7.0-1.json template.jq /
RUN jq -f /template.jq /logstash_7.0-1.json > /logstash.json

# Logstash with the OpenSearch output, the combination Wikimedia
# installs from packages on its logging hosts.
FROM docker.elastic.co/logstash/logstash-oss:8.19.25

# Resolving the plugin's dependencies needs more than JRuby's 1 GB default.
RUN JRUBY_OPTS="-J-Xmx2g" bin/logstash-plugin install --version 2.1.1 logstash-output-opensearch

# Logstash loads the pipeline files in name order: ours (00, 10, 90)
# around Wikimedia's filters, which are unchanged (see wmf/SOURCE).
ENV PIPELINE_ECS_COMPATIBILITY=disabled
RUN rm pipeline/logstash.conf
COPY pipeline/ wmf/*.conf pipeline/
COPY --from=template /logstash.json template/logstash.json
COPY entrypoint.sh /usr/local/bin/mardi-entrypoint

ENTRYPOINT ["/usr/local/bin/mardi-entrypoint"]
