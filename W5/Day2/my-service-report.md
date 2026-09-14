# Service report

Team: team14
Use case: OpenAI-compatible chat completion API served to the paired Agentic AI cohort and used for internal team testing
Service and model: vLLM serving Qwen/Qwen2.5-1.5B-Instruct-AWQ on /v1/chat/completions, namespace team, tier 1 GPU pod
Measured requests or tasks: chat completion requests sent through the traffic.py synthetic client
Indicator and unit: p95 time to first token, seconds
SLO target and window: less than 0.5 s, 5 minute rolling window
Measurement start and end: 2026-09-14 08:19:26 UTC to 2026-09-14 08:22:26 UTC
Workload: traffic.py - one caller for 60s, 30s pause, then four concurrent callers for 60s, responses capped at 64 output tokens, 120 requests completed with 0 failures
Observed result and sample count: 0.037 s p95 TTFT, measured over the 120 completed requests in the run above
Evidence: Grafana Explore reading and the Team service alert rule's own query, checked 2026-09-14 shortly after the traffic.py run
Conclusion: met
Limitations: single short synthetic run with a small 1.5B model and short prompts; not evaluated over a multi-hour production SLO window; no wk-3 concurrency-knee data to say how this holds under heavier load
Follow-up action: repeat this measurement over a longer window with real, non-synthetic traffic before treating the target as a signed SLA


## Measurement query
```
histogram_quantile(
0.95,
sum by (le) (
rate(
vllm:time_to_first_token_seconds_bucket{
job="serving",
instance="team-serving:8000",
model_name="Qwen/Qwen2.5-1.5B-Instruct-AWQ"
}[5m]
)
)
)
```

Measured inside the pod, from queue entry to first token; excludes network and tunnel latency to the consumer.

## Service alert

Condition and unit: p95 time to first token greater than 0.5 seconds
Evaluation interval: 60 seconds
Pending period: 2 minutes
Relationship to the SLO: fires on the same indicator and threshold documented as SLI 1 in my-slo-targets.md (p95 TTFT less than 0.5 s), so a firing alert means the published SLO is already breached, not a separate proxy signal
First response to a notification: First check serving pod health and current request load.

## Notification test

Firing received at: 2026-09-14T08:50:20Z
Resolved received at: 2026-09-14T08:51:00Z
What the test establishes: that the alert-to-webhook notification pipeline (Grafana rule to alert-inbox receiver) delivers firing and resolved events correctly, using an artificial time-based signal independent of real service health — it does not test the actual vLLM service condition.
