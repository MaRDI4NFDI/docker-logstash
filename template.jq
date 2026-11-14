# Adapts Wikimedia's index template (wmf/logstash_7.0-1.json) for a
# single OpenSearch node: no SSD-only allocation, no replicas. It
# also maps "exception" as an object; 10-filter_mardi.conf moves a
# string "exception" aside, so it never clashes.
del(.settings["index.routing.allocation.require.disktype"])
| .settings.number_of_replicas = 0
| .mappings.properties.exception = {
    type: "object",
    properties: {
      class: { type: "keyword" },
      message: { type: "text" },
      code: { type: "keyword" },
      file: { type: "keyword" },
      trace: { type: "text" }
    }
  }
