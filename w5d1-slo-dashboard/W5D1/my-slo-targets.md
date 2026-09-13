# Service indicators and proposed targets

Team: team14
Use case: LLM chat inference service that receives user prompts and generates model responses.
Service measured: Qwen/Qwen2.5-1.5B-Instruct-AWQ, vLLM serving endpoint, namespace team.
Workload: Artificial lab traffic using traffic.py. One caller for 60 seconds, followed by a 30-second quiet period, then four callers for 60 seconds. Maximum output tokens: 64. Total requests: 120.
Measurement period: 2026-09-13 08:25:38 UTC to 2026-09-13 08:28:38 UTC.
Instrumentation gaps: Instrumentation gaps: HTTP status codes are not available in the selected vLLM metrics. Results are based on a short artificial workload of 120 requests, not long-term production traffic.

Complete two SLI sections. Copy one section if you choose a third. Use the exact
stat-panel title for Panel. Keep the field labels so the verifier can read them.
Support each target with observed measurements.

## SLI 1

Indicator: 95th percentile Time to First Token (p95 TTFT)
Panel: p95 Time to First Token
Unit: ms
Target: < 50 ms (provisional operating target for streaming responsiveness)
Window: 5m rolling query window; 1h rolling SLO window
Observed: 39.0 ms under 1 to 4 concurrent callers (traffic.py synthetic workload)
Evidence: histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket{job="serving"}[5m]))) recorded at 2026-09-13 13:15:00 UTC 
Why it fits: Time to first token measures initial model response latency and queue waiting time before streaming starts, representing direct interactive responsiveness to end users.
Limitations: Histogram quantiles are bucket approximations rather than exact timings; limited by an artificial 150-request sample size and requires retesting under prolonged burst loads.

## SLI 2

Indicator: completed requests per minute
Panel: Completed Requests per Minute
Unit: requests/min
Target: at least 20 requests/min (provisional diagnostic threshold, based on this short workload)
Window: 5 minutes
Observed: 25.3 req/min, measured after the traffic.py run ending 2026-09-13T10:38:17Z
Evidence: Grafana panel Completed Requests per Minute, query 60 * sum(rate(vllm:request_success_total{job="serving", finished_reason=~"stop|length"}[5m])), captured 2026-09-13T10:38 UTC after traffic.py run
Why it fits: a low rate under concurrent load means requests start queuing and consumers see slower responses, so this shows whether the pod keeps up with real demand
Limitations: only tested with 4 concurrent callers over ~1 minute, no wk-3 bench data for a real concurrency knee; result may differ under sustained multi-hour load
