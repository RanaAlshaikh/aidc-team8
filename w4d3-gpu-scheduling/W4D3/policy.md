Policy:
Serving is guaranteed because it has the latency SLO, dashboard is allowed to burst, and batch is throttled first because it has no deadline.

serving:
  resources:
    requests:
      cpu: "1"
      memory: 3Gi
    limits:
      cpu: "1"
      memory: 3Gi

batch:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

dashboard:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi

Defense:
The batch workload is configured to throttle first because it has no deadline and is less latency-sensitive than serving. In our test, serving p95 was 7 ms with the unlimited neighbour and 9 ms with the CPU-limited neighbour, so this particular run did not show a measurable latency improvement from limiting the neighbour.
