# Lab W5D2: find the knee, price the fleet

Start:      Sunday's dashboard live, your release healthy. Pin the measurement:
            `kubectl delete hpa team-serving; kubectl scale deployment
            team-serving --replicas=1` (the HPA fighting your ramp makes the
            knee a moving target; it goes back on afterwards).
Objective:  Ramp load in steps against your own stack, read the knee off your
            own dashboard, then turn it into the three numbers operations
            actually asks for: max honest rate at your SLO, replicas for a
            target load, and cost per million tokens at three scenarios.

Time: about 2.5 hours. Tier 0; the method is tier-blind (week 3 did this to
an engine, today you do it to a service, tier 1 does it to the GPU pod).

Week 3 found an engine's knee with a Python harness. Today the same shape
comes back at the service level, measured through the platform you built, read
off the dashboard you published, and priced. The difference matters: week 3's
number was capacity of a process; today's is capacity of the thing your
consumer actually calls, probes and preStop and Service hops included.

## Predict (by hand)

Credited for handing it in, never marked right or wrong - hedged guesses teach nothing, and nothing here is graded for accuracy.

- One replica of your echo-backend service: requests/s at the knee?
- At the knee, which panel moves first: p95, error rate, or neither?
- Your team's published p95 target: what user count first violates it?

## The delta

### Step 1: the ramp (about 40 min)

`locustfile.py` here, stepped by hand so each level is a clean reading. Open the
path and export the key first, because your release has been keyed since
Thursday:

```bash
kubectl port-forward svc/team-serving 8000:8000 &
export AIDC_API_KEY=$(kubectl get secret serving-keys \
    -o jsonpath='{.data.api-key}' | base64 -d)
```

Then for u in 2, 4, 8, 16, 32:

```bash
locust -f locustfile.py --headless -u $u -r $u -t 40s \
  -H http://127.0.0.1:8000 --only-summary
```

The file is Wednesday's request shape plus the bearer header, and it refuses to
start unless one real call comes back 200. That refusal is deliberate: an
unkeyed ramp answers 401 in a quarter of a millisecond, and a 401 is a 4xx, so
your availability panel would read 100%, your p95 would read the bottom of the
histogram, and your throughput would look magnificent. Everything downstream
today is built on these five readings, so the ramp proves it is talking to the
real path before it takes any.

After each level, record from the **dashboard**, not locust's own summary:
requests/min and p95 during the level's window. Locust sees client-side
latency including the forward; the dashboard sees what the service promised.
Both are true; the SLO was published against the dashboard's view.

### Step 2: read the knee (about 20 min)

Plot or tabulate: throughput per level, p95 per level. The knee is the last
level where p95 holds your published SLO while throughput still grew. Name it:
"our knee is N users ≈ R req/min at p95 = L ms". If every level held, your
laptop gave out before your service - say so and use the last measured level;
the method is the deliverable.

### Step 3: capacity arithmetic (about 25 min, by hand)

Fill `capacity-worksheet.md`:

- **Max honest rate** = knee throughput. Anything above it is capacity you do
  not have at your SLO, whatever the cheaper-looking levels past it claim.
- **Replicas for a target**: for double and triple the knee load,
  `ceil(target / knee_rate)` replicas at the same per-replica knee - never
  "push one replica past its knee", which you already measured as SLO-violating.
- Sanity: Wednesday's HPA maxed at 3 - does your replica arithmetic fit under
  it, and what would you raise it to?

### Step 4: price it (about 25 min, by hand)

Tier-0 economics with tier-1 prices, deliberately: assume the team-pod rate
(~$0.60/h A10-class, or the board's current quote) per replica-equivalent.
Cost per million tokens = hourly rate / (tokens-per-hour / 1e6), using your
knee throughput × the lab's ~200 tokens per request. Three scenarios in the
worksheet: steady knee load, double (2 replicas), spiky (double for 4 h/day,
knee otherwise - blended). The punchline you should see: utilisation is the
money metric; the spiky fleet's cost per token is the argument for
autoscaling, in dollars.

### Step 5: the procurement call (about 20 min)

The worksheet's last section gives you three instance shapes priced against
**your** knee as the unit. Fill it as a team: cheapest shape for the steady
scenario, chosen shape for the spiky one, the daily bill for both, and the
one line the sheet cannot price - what buying one big box does to your blast
radius and your rolling update's surge headroom. The morning's decision slide
holds the debrief if you want to check your instinct; your numbers are the
ones that count.

### Step 6: restore and green check

```bash
helm upgrade team ../../../week-04-kubernetes/lab/d4-helm-autoscale/serving-chart \
  --reuse-values --set hpa.enabled=true
kubectl get hpa team-serving          # back, min 1 max 3
python verify.py
```

## Verify (green check)

`verify.py` reads `capacity-worksheet.md`: at least four ramp levels with
throughput and p95, a named knee that is one of the measured levels, replica
counts that are correct ceilings of your own targets over your own knee, and
cost arithmetic that recomputes from your own numbers (formula tolerance 2%).
Wrong-but-consistent measurement passes - it is your hardware; wrong arithmetic
does not. Expected final line: `GREEN CHECK: PASS`.

## Failure modes

- **Throughput climbs at every level and p95 never moves.** The echo backend
  on a strong laptop out-runs a 32-user ramp through one forward. Raise to 64,
  or drop the serving CPU limit to 500m to bring the knee into view; note
  whichever you did in the worksheet.
- **p95 terrible at every level including u=2.** The port-forward is the
  bottleneck (they are single-connection funnels). Use the in-cluster loop or
  a NodePort for the ramp.
- **Locust's p95 disagrees with the dashboard's.** It always will, a little:
  client path vs server histogram, and Prometheus buckets snap. Cite the
  dashboard for SLO claims; cite locust for client experience; do not average
  them.
- **The knee lands between levels.** Then it is a range; the worksheet has a
  line for exactly that. Do not rerun for hours hunting a point - operations
  quotes ranges.
