# Lab W4D4: package it, then let it breathe

Start:      Yesterday's cluster. Delete the hand-written deployment first
            (`kubectl delete deployment serving; kubectl delete service serving`)
            - today the chart owns those objects.
Objective:  Package the stack as a Helm chart, install it as a release, then
            put an autoscaler on it and watch replicas rise under load you
            generate, and fall when you stop.

Time: about 3 hours. Tier 0 throughout. The last 30 minutes are deliberately
reserved for Thursday's tunnel pre-staging (Step 7) - do not skip it, Thursday
morning is crowded enough already.

Two ideas today, and they are separate. Helm: the YAML you wrote Monday and
Tuesday, templated, so one `values.yaml` describes a deploy and one command
applies all of it. Autoscaling: a controller that reads the same metrics
`kubectl top` shows and edits your replica count for you. The second idea is
where LLM serving diverges from the textbook, and the lecture said why: CPU%
is the wrong signal for GPU-bound serving. Today's target IS CPU because the
echo backend is CPU-bound, which makes it the right signal *here* - knowing
why it is right here and wrong on the team pod is the exam question that
matters.

## Predict (by hand)

Credited for handing it in, never marked right or wrong - hedged guesses teach nothing, and nothing here is graded for accuracy.

- `helm install team ./serving-chart` then `helm install shadow ./serving-chart`:
  what exists in the cluster that could not exist with plain `kubectl apply`
  of the same YAML twice?
- The HPA targets 50% of a 250m CPU request. Your load pushes each pod to
  ~300m. How many replicas does the controller want? (The formula is in the
  deck; do the arithmetic.)
- When the load stops, do replicas drop immediately? What is the risk if they
  did?

## The delta

### Step 1: metrics-server, the eyes (about 15 min)

The HPA reads pod CPU from the metrics API, which kind does not ship. The
manifest here is the upstream release with one added flag,
`--kubelet-insecure-tls`, because kind's kubelets use self-signed certs -
without it metrics-server never becomes Ready and every HPA shows `<unknown>`.

```bash
kubectl apply -f metrics-server.yaml
kubectl -n kube-system rollout status deployment/metrics-server
kubectl top pods -A | head        # numbers, not errors, before you continue
```

### Step 2: read the chart (about 20 min)

`serving-chart/` is Monday's deployment.yaml and service.yaml with the values
pulled out: image, replicas, backend, resources, and an `hpa:` block. Open
`templates/deployment.yaml` next to your Monday file: every hard-won detail
(probes, `maxUnavailable: 0`, the preStop sleep) survived into the template.
Helm adds no new Kubernetes ideas - it fills blanks.

```bash
helm template team ./serving-chart | less     # exactly what would be applied
```

### Step 3: install it as a release (about 20 min)

```bash
helm install team ./serving-chart --set image=<your-user>/aidc-serving:cpu-v1
kubectl rollout status deployment/team-serving
helm list
```

Rename nothing by hand: the release name prefixes the objects
(`team-serving`), which is what lets a second release coexist. Prove it:

```bash
helm install shadow ./serving-chart --set image=<your-user>/aidc-serving:cpu-v1
kubectl get deployments
helm uninstall shadow
```

### Step 4: turn the autoscaler on, under your policy (about 20 min)

The morning's decision slide gave your team a scaling policy. The chart's
values expose exactly its three dials. Enable the HPA **with your dials**, not
the defaults:

```bash
# Aggressive:    --set hpa.targetCPUPercent=30 --set hpa.maxReplicas=5 --set hpa.scaleDownStabilizationSeconds=30
# Conservative:  --set hpa.targetCPUPercent=70 --set hpa.maxReplicas=3 --set hpa.scaleDownStabilizationSeconds=300
# Cost-capped:   --set hpa.targetCPUPercent=50 --set hpa.maxReplicas=2

helm upgrade team ./serving-chart --set image=<your-user>/aidc-serving:cpu-v1 \
  --set hpa.enabled=true <your policy's three flags>
kubectl get hpa team-serving -w     # leave watching; <unknown> resolves within a minute
```

Write your policy's predictions on the card before the load starts: final
replica count under the standard 24-worker load, and whether `/health` p95
holds through the surge (reuse yesterday's latency probe if you want the
number, not the feeling).

Note what the chart did when the HPA took over: the Deployment's own
`replicas:` line is gone from the template (`{{- if not .Values.hpa.enabled }}`),
because two controllers fighting over one number is a real production bug, not
a hypothetical.

### Step 5: load, and watch it breathe (about 40 min)

In-cluster load, using your own image as the generator (24 threads of chat
completions against the release's Service):

```bash
kubectl run loadgen --image=<your-user>/aidc-serving:cpu-v1 --restart=Never --command -- \
  python -c '
import json, threading, time, urllib.request
BODY = json.dumps({"model": "Qwen/Qwen2.5-0.5B-Instruct", "messages": [
    {"role": "user", "content": "repeat the word load " * 60}], "max_tokens": 200}).encode()
def worker():
    end = time.time() + 240
    while time.time() < end:
        try:
            req = urllib.request.Request("http://team-serving:8000/v1/chat/completions",
                                         data=BODY, headers={"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=10).read()
        except Exception:
            time.sleep(0.2)
threads = [threading.Thread(target=worker) for _ in range(24)]
[t.start() for t in threads]
[t.join() for t in threads]
'
```

Keep the `-w` from Step 4 visible next to it. What you should see, with rough
timing from the reference run on the build machine: within ~30 s the target
column crosses 50%, and at ~51 s the HPA raises desired replicas in one
clamped jump, 1 straight to `maxReplicas: 3` (the arithmetic wanted 8; the
clamp said 3 - the deck's worked example). The new pods are Running within a
couple of minutes. When the generator exits (4 min), the
percentage collapses, and about one stabilization window later (60 s in the
chart's values, shortened from the 300 s default so you can watch it) the
replicas walk back down. Write both timestamps on your card - scale-out and
scale-in - quiz 3 asks for them.

If you prefer load from your laptop instead of in-cluster, `locustfile.py`
here is pre-tuned for a 4-core machine through a port-forward; the cluster
does not care where the load comes from.

The reference timings above came from the default policy (50%, max 3, 60 s).
Yours will differ **by your policy's design**: aggressive tables hit their
ceiling sooner and walk down almost immediately, conservative tables may spend
the whole first minute at one replica while their p95 wears the surge, and
cost-capped tables plateau at 2 with the target percentage pinned high. At
day's end, compare final replica count and p95 across tables: same load, three
policies, three different pains - all of them chosen, none of them bugs.

### Step 6: the baseline's failure analysis (about 15 min)

Before Thursday makes this public, write down what you are shipping. Today's
scaler watches CPU because the echo backend spends CPU per token. The team-pod
engine does not: vLLM is GPU-bound, its CPU idles near 5% while the real queue
drowns, and this exact HPA would read 4%/50% and hold one replica through an
outage.

In `hpa-failure-analysis.md` next to this README (plain text, a few lines):

1. Where today's scaler fails on the real engine, in your own words.
2. The signal you would deploy instead - in-flight requests, engine queue
   depth (`vllm_num_requests_waiting`), or KV-cache utilization - and why that
   one for YOUR workload.
3. The target number you would start with, and what you would watch to tune it.

There is no verifier for this file; Thursday's go-live review reads it, and
next week's stack measures the signal you named.

### Step 7: pre-stage Thursday (the last 30 min, not optional)

Thursday morning is go-live. The one mechanical thing it needs that takes
unpredictable time is a public URL, so prove the whole tunnel path NOW, while
nothing depends on it. You installed `cloudflared` on Sunday (W4D1 Step 1);
run one hello-world through it:

```bash
kubectl port-forward svc/team-serving 8000:8000 &
cloudflared tunnel --url http://localhost:8000   # prints https://<random>.trycloudflare.com
# from your PHONE on hotspot (not this machine): open https://<random>.trycloudflare.com/health
# then tear it down: Ctrl-C the tunnel, kill %1 for the forward
```

The `{"status": ...}` reply on a phone that shares nothing with your laptop is
the proof. If the tunnel never prints a URL, the usual suspects are corporate
or campus networks blocking the outbound connection - switch to a hotspot and
retry, and tell the instructor tonight, not Thursday. (No cloudflared? The
W4D1 install block has the pinned download line for every OS.)

### Step 8: green check

```bash
bash verify.sh
```

## Verify (green check)

`verify.sh` checks metrics are flowing (`kubectl top` answers), the release
exists and its rendered spec kept the Monday details (probes, preStop,
`maxUnavailable: 0`), the HPA is present with the chart's bounds, and then
observes a real scale event: it starts its own load generator and waits for
desired replicas to rise above minReplicas. Takes about four minutes.
Expected final line: `GREEN CHECK: PASS`.

## Stretch

Add a `values-tier1.yaml` that swaps the echo backend for the vLLM image and
one GPU (yesterday's `vllm-gpu.yaml`, as values). `helm template` it - do not
apply it on kind - and diff the render against tier 0. One chart, two tiers,
which is the entire pitch of Helm in this course.

## Failure modes

- **HPA shows `<unknown>` forever.** metrics-server is not Ready, and on kind
  that is the missing `--kubelet-insecure-tls` in 90% of cases. Confirm with
  `kubectl -n kube-system logs deployment/metrics-server | tail`.
- **Load runs, CPU% stays near zero.** The generator is hitting a pod that
  is not there (`team-serving` spelling includes the release name) or your
  requests are so large that real usage is a rounding error against them. The
  chart's 250m request is tuned to the echo backend; if you raised it to
  match Tuesday, put it back for this lab.
- **Replicas hit max and never come down.** The stabilization window has not
  elapsed, or the generator is still running (`kubectl get pod loadgen`).
  Patience is part of the control loop; that is the lesson, not a bug.
- **`helm upgrade` says the deployment field is immutable.** You changed the
  selector labels between installs. Uninstall and reinstall the release;
  selectors are forever within one Deployment's lifetime.
- **Two releases, one HPA fight.** If you installed `shadow` with
  `hpa.enabled=true` too and both scaled, your laptop is now running up to six
  pods. That is working as designed; uninstall what you do not need.
