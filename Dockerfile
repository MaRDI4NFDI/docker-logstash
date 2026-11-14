# Logstash with the OpenSearch output, the combination Wikimedia
# installs from packages on its logging hosts.
FROM docker.elastic.co/logstash/logstash-oss:8.19.25

# Resolving the plugin's dependencies needs more than JRuby's 1 GB default.
RUN JRUBY_OPTS="-J-Xmx2g" bin/logstash-plugin install --version 2.1.1 logstash-output-opensearch
