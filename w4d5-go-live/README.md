# Lab W4D5: go-live

Start:      Wednesday's release (`helm status team` green), the tunnel binary
            from Wednesday's Step 7, and quiz 3 already behind you (it ran in
            the morning block).
Objective:  Put a bearer key on the service, expose it beyond your machine,
            prove it from the outside, start its metrics history, and hand
            your paired Agentic AI team the note that makes you their
            platform.

Time: about 3 hours, and the order is the point: key first, then exposure,
then proof, then paper. Nothing gets exposed open, even for a minute, even to
"just test it".

Today the course's sentence about you changes tense: you stop building a
service and start operating one. From the moment the smoke test passes from
outside, the uptime watch is on and downtime is visible to the class. That
pressure is deliberate, and it is also why everything below is mechanical: on
go-live day you want no decisions left, only steps.

## Predict (by hand)

Credited for handing it in, never marked right or wrong - hedged guesses teach nothing, and nothing here is graded for accuracy.

- Your endpoint goes through a tunnel from your laptop. Name the two things
  that can now take it down that have nothing to do with Kubernetes.
- The agentic cohort's client sets `base_url` to your URL and changes nothing
  else. What is the first request their framework will actually send: a chat
  completion, or something else? (Think about what their client does on
  startup.)
- Your published TTFT p95 at tier 0 (CPU, echo) versus tier 1 (GPU, vLLM):
  which SLO numbers can you honestly promise today, and which are placeholders
  until the team pod exists?

## The delta

### Step 1: the key goes on first, as a Secret (about 20 min)

Week 2 promised this day: "the key comes from a Kubernetes Secret that either
exists or does not." Create it, then point the chart at it:

```bash
kubectl create secret generic serving-keys \
  --from-literal=api-key=$(python3 -c "import secrets; print(secrets.token_hex(16))")
helm upgrade team ./../d4-helm-autoscale/serving-chart \
  --set image=<your-user>/aidc-serving:cpu-v2 \   # the wk-2 close: auth shipped as cpu-v2; cpu-v1 predates the key
  --set hpa.enabled=true \
  --set apiKeySecret=serving-keys
kubectl rollout status deployment/team-serving
```

Why not `--set apiKey=<the key>`? Because that literal would live on in your
shell history, in `helm get values`, and in every rendered manifest - three
places a secret has no business being. The Secret path leaves the chart
holding only a *name*. Read the key back when you need it:

```bash
kubectl get secret serving-keys -o jsonpath='{.data.api-key}' | base64 -d; echo
```

That `base64 -d` is the day's small disillusionment: Secrets are base64
**encoded**, not encrypted - anyone with cluster access reads them. The win is
scoping and rotation (delete the Secret, roll the deployment, the old key is
gone everywhere at once), not cryptography.

Two keys exist in the real setup: one for your team, one you will hand the
agentic team. At tier 0 one key carries both roles; the tier-1 runbook issues
them separately.

Prove the lock before exposing anything:

```bash
kubectl port-forward svc/team-serving 8000:8000 &
curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/v1/models          # 401
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer <key>" \
  localhost:8000/v1/models                                                 # 200
curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/health             # 200: probes stay open
```

### Step 2: the wk-4 delta, then the metrics history (about 35 min)

The scrape below reads `/metrics` - a route your wk-2 image does not have yet.
It landed upstream this week as the wk-4 serving-stack delta. Pull it into
your fork, rebuild, and push the week's tag:

```bash
git fetch upstream && git merge upstream/main   # brings app/main.py's /metrics block
docker build -t <your-user>/aidc-serving:cpu-v3 .
docker push <your-user>/aidc-serving:cpu-v3
kind load docker-image <your-user>/aidc-serving:cpu-v3 --name aidc
helm upgrade team ../d4-helm-autoscale/serving-chart   --reuse-values --set image=<your-user>/aidc-serving:cpu-v3
kubectl rollout status deployment/team-serving
curl -s localhost:8000/metrics | head -3        # through your port-forward: aidc_ lines
```

(If the merge conflicts, `git checkout upstream/main -- app/main.py` takes the
upstream file wholesale; your wk-2 work lives in the same file upstream built
on, so conflicts mean you diverged - read the diff before stomping it. And if
you ever rebuild the SAME tag: kind keeps serving the old bits until you
`kind load` again and then `kubectl rollout restart deployment/team-serving` -
an unchanged tag never rolls by itself.)

Now the history:

Given, not taught. Week 5 teaches what this is; today it just starts
recording so that Sunday's dashboards open onto history instead of a blank
graph:

```bash
kubectl apply -f prometheus-scrape.yaml
kubectl rollout status deployment/prometheus
kubectl port-forward svc/prometheus 9090:9090 &
curl -s 'localhost:9090/api/v1/query?query=aidc_requests_total' | head -c 200   # series exist
```

### Step 3: expose it (about 30 min)

Tier 0 truth first: kind lives on your laptop, so the public URL terminates at
your laptop and the tunnel is part of your service now. Wednesday's pre-staged
tunnel does the work:

```bash
# Step 1's forward may still be running; one is enough. If 8000 is taken,
# kill the old one first: kill %1 (or pkill -f 'port-forward svc/team-serving')
kubectl port-forward svc/team-serving 8000:8000 &
cloudflared tunnel --url http://localhost:8000        # prints https://<random>.trycloudflare.com
```

On the team pod (tier 1) this step is where the real path diverges: k3s
exposes a NodePort on the pod's public IP, the tunnel disappears, and the URL
stops depending on anyone's laptop. Same contract, different plumbing; the
integration note does not care which one it describes.

### Step 4: the outside-in smoke test (about 20 min)

Not from your machine. From a teammate's, or a phone on hotspot. The test is
the exact call your consumer will make:

```bash
curl -s https://<your-url>/v1/models -H "Authorization: Bearer <key>"
curl -s https://<your-url>/v1/chat/completions -H "Authorization: Bearer <key>" \
  -H 'Content-Type: application/json' \
  -d '{"model":"<from /v1/models>","messages":[{"role":"user","content":"hello from outside"}]}'
```

Send one real request before you tell anyone it is ready. The runbook's
before-it-opens checklist says exactly this, because "it worked on my machine"
has ended more integrations than any outage.

### Step 5: the integration note (about 25 min)

Copy the template, then fill your copy - filling the template in place
destroys it for the next run:

```bash
cp integration-note.md my-integration-note.md
```

Fill `my-integration-note.md`, every angle bracket, including the modality line
your team already answered at week-2 formation and the SLOs you can honestly
sign at your tier. The key is handed over in person or to their on-call, never
written into the note. This note is the contract the next three weeks run on;
week 6's traffic market trades against the SLOs you publish here.

### Step 6: the acceptance desk (about 25 min)

Swap notes with another AIDC team (the desk pairing - your Agentic AI pair
is next week's customer, today's reviewer sits in this room). You review
theirs while they review
yours, and the rule is symmetrical: **the note alone**. No verbal help, no
pointing at screens. From your own machine, against their URL:

1. `GET /v1/models` with their documented auth - does the model id match the
   note?
2. One chat completion, exactly their example call.
3. One call **without** the key - anything but 401 is an outright rejection.
4. Read their SLOs against what you just measured: is the window stated, and
   could this tier honestly sign these numbers?

Write the verdict at the bottom of their `my-integration-note.md`, one line: `ACCEPTED <date>
<your team>` or `REJECTED: <the reason, named>`. A rejection is a fix-and-
requeue, not a grade - but the fix happens before the watch entry, because a
customer just did what the Agentic AI cohort does next week and it did not
work.

While the desk runs, one teammate defends the week's badge at the reviewing
table: two minutes, their pick of who speaks - show the roll that dropped
zero, name who throttles first on your node, say which signal scales the real
engine and how today's fails it.

### Step 7: enter the uptime watch (about 10 min)

Post your URL and team name where the instructor's watch page collects them.
From here, the status page checks `/health` once a minute, and the history is
part of your capstone evidence (the wk-6 dark day scores from the same watch).

### Step 8: green check

```bash
bash verify.sh https://<your-url> <key>
```

## Verify (green check)

`verify.sh` takes your public URL and key and checks the whole posture from
outside the cluster: `/health` open, `/v1/models` locked without the key and
serving with it, a real completion answering, `/metrics` scraped by the
in-cluster Prometheus (it queries Prometheus for your request counter), and an
integration note with no angle brackets left in it. Expected final line:
`GREEN CHECK: PASS`.

## Stretch

Kill the port-forward behind the tunnel and watch what your consumer would
see. Bring it back. That gap is Monday's lecture (operating for someone else)
arriving two days early, and it is the argument the tier-1 compute memo makes
in one sentence.

## Failure modes

- **401 even with a key.** The key you are sending is not the one in the
  Secret. Read the live one back:
  `kubectl get secret serving-keys -o jsonpath='{.data.api-key}' | base64 -d`.
- **The door is open again after an upgrade.** The chart injects `API_KEY` only
  while `apiKeySecret` sits in the release's values, and a `helm upgrade`
  without `--reuse-values` drops it. `helm get values team` is the truth; carry
  `--reuse-values` on every upgrade after Step 1.
- **Tunnel URL answers 502.** The tunnel points at `localhost:8000` but the
  port-forward behind it died (they do, silently, when pods roll). Restart the
  forward; on the team pod this class of failure disappears.
- **Prometheus target down.** The scrape config names `team-serving:8000`; if
  your release is not called `team`, edit `prometheus-scrape.yaml` to match.
- **Smoke test passes from your machine and fails from outside.** Corporate
  or campus network blocking the tunnel domain, or the free-tunnel rate limit.
  Try the phone-hotspot path before debugging Kubernetes; the cluster is the
  last suspect here, not the first.
- **`/v1/models` returns a model id your note did not promise.** You changed
  `modelId` in values at some point today. The note, the release, and the
  smoke test must agree character for character; the consumer's client checks.
