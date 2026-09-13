# Lab W5D1: the SLO dashboard

Start:      Thursday's go-live state: release up, keyed, and the given
            Prometheus recording since go-live (`kubectl get deployment
            prometheus` exists). If your history is thin or gappy, the STAFF
            datasource below has the backfill.
Objective:  Stand Grafana up in the cluster, build the four-panel SLO
            dashboard over your own metrics history, and publish the SLO
            targets your team will be measured against for the rest of the
            course.

Time: about 2.5 hours. Tier 0 (aidc_* metrics). Tier 1 swaps the queries to
vLLM's families - same shapes, noted at the bottom.

Since Thursday your service has been writing history: every request, every
latency, every status code, scraped each 15 seconds into Prometheus. Today
that history becomes four numbers you choose to stand behind. The dashboard is
not decoration - Thursday's game day is scored against it, week 6's traffic
market trades on it, and the capstone rubric reads it.

## Predict (by hand)

Credited for handing it in, never marked right or wrong - hedged guesses teach nothing, and nothing here is graded for accuracy.

- Your availability over the last 24 h, as a percentage, from memory of what
  happened since go-live. Write it; the first panel will grade your intuition.
- Your e2e p95 right now, in ms. (You measured this stack in week 3.)
- Which panel will look worst: availability, p95, throughput, or errors?

## The delta

### Step 1: Grafana, given (about 15 min)

`grafana.yaml` here is complete - plumbing is not today's lesson:

```bash
kubectl apply -f grafana.yaml
kubectl rollout status deployment/grafana
kubectl port-forward svc/grafana 3000:3000 &
```

Open `http://localhost:3000`. Anonymous admin, one datasource already pointed
at your Prometheus. If Explore > `aidc_requests_total` returns series, you
have history; if it is empty, fix Thursday's scrape before building anything
on top of it.

### Step 2: the four SLIs, as queries first (about 40 min)

Build each in Explore before it becomes a panel. Type them; the reference
solutions are in `slo-dashboard.json` for when you are stuck, not for pasting.

- **Availability** (1h): non-5xx completions over all completions, as a
  percentage. You need `rate()`, a `code=~"5.."` matcher, and `clamp_min` so
  an idle hour divides by something.
- **e2e p95** (5m): `histogram_quantile(0.95, ...)` over
  `aidc_request_latency_seconds_bucket`. This is the same histogram-to-p95
  move week 3's benchmark harness did in Python.
- **Requests/min** (5m rate × 60).
- **Error rate** (5m): the 5xx ratio again, tighter window.

### Step 3: the dashboard (about 40 min)

New dashboard, four stat panels across the top (availability gets thresholds:
red under 99, green at 99.5), two timeseries beneath (latency percentiles p50/
p95/p99; traffic by status code). Set refresh to 10 s. Save as
`Team SLOs`.

The morning's critique rule applies to your own work now: every panel's
**description field** carries one line stating the question the panel answers
("are we keeping the promise", "how does it feel right now"). A panel whose
question you cannot write in one line is the fourteen-series panel from the
critique - delete it. The five sins are the review checklist; run your own
dashboard against them before you call Step 3 done.

Then make it real: with your load generator running, kill a pod (Monday's
move) and watch the availability stat flinch and recover on the panel.

### Step 4: publish your targets (about 25 min)

Copy `slo-targets.md` to **`my-slo-targets.md`** (the green check reads that
name), fill it as a team, commit it to your repo, and post it where the class
publishes targets. Three numbers and their windows:
availability %, p95 ms, error rate % - chosen from your own history, not from
hope. The rubric measures you against what you publish here, and game day
scores detection against these exact thresholds.

<div class="callout">A target you beat every quiet afternoon and miss under any
load is a wish. Read your own worst hour first (`[24h]` panels), then choose.</div>

### Step 5: green check

```bash
bash verify.sh
```

## Verify (green check)

`verify.sh` checks Grafana is up and provisioned, your dashboard exists with
the four SLI panel types and a latency timeseries, the availability query
actually returns a value through Grafana's datasource proxy, and
`my-slo-targets.md` is filled with numeric targets. Expected final line:
`GREEN CHECK: PASS`.

## Tier 1 and the backfill

- Tier 1: same dashboard, vLLM's series. vLLM publishes them as
  `vllm:e2e_request_latency_seconds_bucket`, `vllm:request_success_total`,
  `vllm:num_requests_running`, `vllm:gpu_cache_usage_perc`, colons and all.
  **What your TSDB stores is box-dependent, so check before you build.**
  Prometheus 2.55 asks scrape targets for underscore escaping, and a
  `prometheus_client` new enough to honour that stores `vllm_*`, while an
  older one stores `vllm:*` verbatim; both have been observed on real course
  boxes (colons on the 2026-08-13 A6000 pod, underscores on the 2026-08-21
  build box). The failure is quiet either way: an unknown metric name in
  PromQL is an empty result, and an empty panel looks exactly like an idle
  service. So before building a single panel, ask the TSDB what it holds:
  Explore, `{__name__=~"vllm.*"}`, and write every query in the spelling that
  comes back. The exposition page (`curl -s localhost:8000/metrics`) always
  shows colons, which makes it the wrong place to settle this.
- Gappy history: add the STAFF Prometheus as a second (read-only) datasource -
  URL on the board - and build against it; swap the datasource back to yours
  once your own history fattens. The lab never blocks on your Thursday.

## Failure modes

- **Explore returns nothing.** The scrape is down or was never applied:
  `kubectl get deployment prometheus`, then the targets page
  (port-forward 9090, /targets). Fix the pipe before the panels.
- **Availability shows 100% forever.** You have no 5xx in history - likely
  true! Prove the query works by making one: request with a wrong model id...
  that is a 400, not a 5xx. Kill the pod mid-request instead, or accept that a
  clean history reads 100 and move on; the panel earns its keep Thursday.
- **p95 flat at one of the bucket edges.** Histogram quantiles snap to bucket
  boundaries - the app's buckets are fixed. That is a property of histogram
  math, not a bug; week 3's harness had exact latencies, Prometheus trades
  exactness for cheapness. Say this in your targets file if it bites yours.
- **`histogram_quantile` returns NaN.** No samples in the window - your rate
  window is narrower than one scrape interval, or traffic stopped. Widen to
  `[5m]` and check the generator.
