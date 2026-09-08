# Lab W4D3: GPUs in the scheduler's ledger

Start:      Yesterday's Deployment + Service running in kind.
Objective:  Make scheduling visible as accounting: put requests and limits on
            your serving pods, read what the scheduler does when the ledger
            does not balance, including for a GPU that is not there, and
            measure what a CPU limit does to a noisy neighbour.

Time: about 2 hours at tier 0. The tier-1 half (vLLM scheduled onto the team
GPU pod) is a separate track at the end; run it when your team pod exists.

Kubernetes never measures how much a pod uses to decide placement; it adds up
what pods *request* and refuses what does not fit. GPUs enter the same ledger
as `nvidia.com/gpu: 1`, a countable resource like CPU, except it only exists
on nodes where the device plugin advertises it. Today you read that ledger,
overdraw it on purpose twice, and then see the other half: what limits do
after placement.

## Predict (by hand)

Credited for handing it in, never marked right or wrong - hedged guesses teach nothing, and nothing here is graded for accuracy.

- Your node has some number of CPUs (`kubectl describe node`, Capacity). If a
  pod requests 64 CPUs, what exactly happens: an error on apply, a pod that
  crashes, or something else?
- A pod requests `nvidia.com/gpu: 1` on your kind node, which has no GPU and
  no device plugin. Same question. Will the error message name the GPU?
- A neighbour pod burns all the CPU it can get with no limit. Your serving
  pod's `/health` latency: unchanged, somewhat worse, or catastrophically
  worse? Now the neighbour gets `limits: cpu: 500m`. What changes?

## The delta

### Step 1: give the serving pods a ledger entry (about 20 min)

Add to the serving container in `deployment.yaml`:

```yaml
          resources:
            requests:
              cpu: 250m          # what the scheduler reserves
              memory: 256Mi
            limits:
              cpu: "1"           # what the runtime enforces
              memory: 512Mi
```

```bash
kubectl apply -f ../d2-self-healing/deployment.yaml   # or wherever yours lives
kubectl rollout status deployment/serving
kubectl describe node | grep -A8 'Allocated resources'
```

The node's ledger now shows your requests. Requests decide placement; limits
decide what happens at runtime. Keep the two ideas separate all day.

### Step 2: overdraw the ledger (about 15 min)

```bash
kubectl apply -f impossible-cpu.yaml
kubectl get pod impossible-cpu          # Pending, and it will stay Pending
kubectl describe pod impossible-cpu | tail -5
```

No error on apply: the API accepted a perfectly valid wish. The scheduler just
cannot grant it, and the Events line says why in accounting language:
`Insufficient cpu`. Delete it (`kubectl delete -f impossible-cpu.yaml`).

### Step 3: request a GPU that is not there (about 20 min)

```bash
kubectl apply -f wants-a-gpu.yaml
kubectl get pod wants-a-gpu
kubectl describe pod wants-a-gpu | tail -5
```

`Insufficient nvidia.com/gpu`. Read it twice, because this exact line is what
a mis-scheduled GPU workload looks like on a real cluster: not a crash, not a
CUDA error, a pod that sits Pending while the scheduler shrugs. On the team
pod (tier 1), the NVIDIA device plugin is what advertises the resource and
makes this same manifest schedulable; the manifest does not change, the node
does. Delete the pod when done reading.

### Step 4: the noisy neighbour, measured (about 35 min)

Two runs of the same experiment. Both burner manifests carry the placeholder
image line, and unlike everything above they have to actually run: **edit the
image line in `burner-unlimited.yaml` and `burner-limited.yaml` to your own
image first**, then check the pods reached `Running` before you trust a
latency number. First, chaos with no limit:

```bash
# edit the image line, then:
kubectl apply -f burner-unlimited.yaml
kubectl get pods -l app=burner-unlimited     # both Running, or the run is void
# your in-cluster prober from yesterday, but timing each request:
kubectl run latency-probe --image=<your-user>/aidc-serving:cpu-v1 --restart=Never --command -- \
  python -c '
import time, urllib.request
lat = []
fails = 0
end = time.time() + 30
while time.time() < end:
    t0 = time.time()
    try:
        urllib.request.urlopen("http://serving:8000/health", timeout=5).read()
        lat.append(time.time() - t0)
    except Exception:
        lat.append(5.0)   # count a timeout as its full 5s, not as silence
        fails += 1
    time.sleep(0.05)
lat.sort()
if lat:
    print(f"LATENCY n={len(lat)} fails={fails} p50={lat[len(lat)//2]*1000:.0f}ms p95={lat[int(len(lat)*0.95)]*1000:.0f}ms")
else:
    print(f"LATENCY n=0 fails={fails} (nothing answered at all)")
'
kubectl logs latency-probe   # wait for Completed first; note the numbers
kubectl delete pod latency-probe && kubectl delete -f burner-unlimited.yaml
```

Then the same burner with `limits: cpu: 500m` (`burner-limited.yaml`), same
probe, compare p95s. The serving pods' own `requests` (Step 1) plus the
burner's limit are what keep the second run flat. Record both p95s on your
card; quiz 3 asks for your own numbers.

### Step 5: the policy your numbers justify (about 25 min)

You now hold evidence: a p95 with an unbounded neighbour and a p95 with a
throttled one. Turn it into policy. The scenario is the morning's node - 4
CPUs, three tenants:

- **serving** (your endpoint, p95 SLO, bursty),
- **batch** (an embedding backfill, no deadline today),
- **dashboard** (tiny, spiky on refresh).

Write, in `policy.md` next to this README's other artifacts (plain text, no
template):

1. One sentence of policy, in words, naming who is guaranteed, who bursts,
   and who throttles first.
2. The `resources:` block for each tenant that implements the sentence.
3. One line defending the loser, citing your two p95s as the evidence.

Sanity checks against the morning: serving guaranteed means its requests
cover the burst you actually measured, batch first-to-throttle means its
limit binds while its request stays low, and whatever you give the dashboard,
`kubectl describe pod` will label each tenant's QoS class - check the three
classes match your sentence (`Guaranteed` / `Burstable` / `BestEffort`).

There is no verifier for judgment; the defense is the deliverable, and
Thursday's go-live review reads it.

### Step 6: green check

```bash
bash verify.sh
```

## Verify (green check)

`verify.sh` checks the live serving spec carries both requests and limits,
then performs Step 3's experiment itself: it creates a doomed GPU pod, waits
for the scheduler's verdict, and demands the event text names
`nvidia.com/gpu` before cleaning up. Expected final line: `GREEN CHECK: PASS`.

## Tier 1: the same ledger, with the GPU real

On the team pod (k3s + NVIDIA device plugin installed per
`instructor/tier1-pod-runbook.md`), the flow inverts: `wants-a-gpu.yaml`
schedules, and vLLM serves from inside the cluster. `vllm-gpu.yaml` here is the
manifest: the vLLM OpenAI image, your model-lock.md id with the PINS canon flags
(`--dtype half`, `--max-model-len 4096`, `--gpu-memory-utilization 0.85`, the
parser your lock records), a full ledger entry in both requests and limits, and
a generous startup probe because engines load slowly. Create the key Secret first
(`kubectl create secret generic serving-keys --from-literal=api-key=<key>`) -
the manifest reads it by reference, the way Thursday's chart does. These are
the exact flags your team verified on the T4 in week 3; `kubectl logs` shows
the same startup lines you saw there.

Two things in that manifest are today's own steps applied to a real engine, and
both are worth reading before you apply it.

Its ledger entry is `cpu` and `memory` as well as `nvidia.com/gpu`, requests
equal to limits. A GPU on its own buys no QoS class at all: Kubernetes computes
QoS from cpu and memory only, so a pod requesting nothing but `nvidia.com/gpu`
comes out `BestEffort`, the class Step 5 has you nominate as first to throttle.
Check it yourself once the pod is up, because it is the same `kubectl describe`
habit Step 5 asks for:

```bash
kubectl get pod -l app=vllm -o jsonpath='{.items[0].status.qosClass}'   # Guaranteed
```

Its Service is called `team-serving`, not `vllm`, and that is not cosmetic.
Kubernetes injects a Docker-link environment variable into every pod in the
namespace for every Service, so a Service named `vllm` sets
`VLLM_PORT=tcp://10.43.x.x:8000` in the engine's own environment. vLLM reads
`VLLM_PORT` as its listening port, tries to parse that as an integer, and the
engine dies. `team-serving` is also the name Thursday's Prometheus already
scrapes, so the go-live metrics config needs no tier-1 variant.

Verify the whole path before you call it up:

```bash
kubectl port-forward deploy/vllm 8000:8000 &
curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/health          # 200, open
curl -s -o /dev/null -w '%{http_code}\n' localhost:8000/v1/models       # 401, keyed
curl -s -H "Authorization: Bearer <your key>" localhost:8000/v1/models  # your model id
```

## Stretch

The plugin can also lie on purpose: NVIDIA's device plugin supports
**time-slicing**, where one physical card is advertised as N schedulable
`nvidia.com/gpu` slots. On the team pod, edit the plugin's config to advertise
4 slots and confirm the node's allocatable count goes from 1 to 4 without a
second card appearing. Then scale `vllm-gpu.yaml` to two replicas.

Do it twice. First leave `--gpu-memory-utilization` at the canon 0.85, and watch
the second pod get scheduled, get admitted, and die anyway. Then set both to
0.4 and watch them coexist. Read `nvidia-smi` on the node in each case.

That pair is the whole lesson, and it is sharper than two engines running
politely. The scheduler admitted the second pod because the plugin said there
was a slot, and the plugin says whatever it is configured to say. VRAM is not in
the ledger, so nothing in Kubernetes stopped a pod from asking one card for 170%
of its memory. Time-slicing changes how many pods are admitted, never how much
memory exists. Explain to your card which of those two numbers you actually
control, and what isolation you gave up to get the second pod on.

Tier 0: read the plugin's time-slicing README and write the two-sentence version
instead.

## Failure modes

- **`impossible-cpu` schedules instead of Pending.** Your node has more CPU
  than the manifest asks for (some machines are large). Raise the request in
  the manifest until it overdraws yours; the number is not the lesson.
- **The GPU pod shows `Insufficient cpu` instead of `nvidia.com/gpu`.** Both
  can be insufficient at once and the scheduler reports one. `wants-a-gpu.yaml`
  deliberately requests only the GPU so this cannot happen as shipped; if you
  added a CPU request while experimenting, remove it so the GPU is the only
  thing missing.
- **Step 4 shows no latency difference at all.** First suspect: the burners
  never ran. `kubectl get pods -l app=burner-unlimited` showing
  `InvalidImageName` means the image line is still the placeholder, so nothing
  burned any CPU and both runs are the same idle cluster. Fix the image line
  and re-run before reading anything into the numbers. If both burner pods are
  genuinely `Running`, then your machine has enough idle cores that two burners
  cannot crowd two serving pods. Scale the burner
  (`replicas: 4` or `6`) until the unlimited run visibly hurts, then compare.
  On a big desktop (16+ threads) even that may not bite - `/health` is
  microseconds of work and the kernel schedules it fairly. The honest fix
  there is to shrink the arena instead: recreate kind with a CPU cap
  (`docker update --cpus 4 aidc-control-plane`, then restart the container)
  or accept the null result and read the reference pair; the mechanism is the
  limit, not your particular core count.
- **`describe node` shows requests over 100%.** Requests can exceed capacity
  only if pods were admitted before... they cannot. You are reading the
  *limits* column; limits may oversubscribe, requests may not. That asymmetry
  is the design.

### Tier 1 only

- **The vLLM pod is Running, then exits with `RuntimeError: Failed to infer
  device type`.** The container was given no GPU, whatever the ledger says. The
  scheduler still debited `nvidia.com/gpu 1` from the node, so `describe node`
  looks correct and a second GPU pod queues behind a card nobody is using. The
  error names no device, no driver and no plugin, which is why it reads as a
  vLLM problem. It is a node problem: the pod ran under `runc` instead of the
  NVIDIA runtime. Provision per `instructor/tier1-pod-runbook.md`, which installs
  k3s with `--default-runtime nvidia`. Confirm with
  `kubectl exec <pod> -- nvidia-smi -L` before touching any flag in the manifest.

- **The vLLM pod exits with `ValueError: invalid literal for int() with base 10:
  'tcp://10.43.x.x:8000'`.** Something in this namespace is a Service named
  `vllm`. Kubernetes writes a Docker-link environment variable for every Service
  into every pod, so that Service sets `VLLM_PORT`, and vLLM reads `VLLM_PORT` as
  its own port setting. Rename the Service to `team-serving`. Note the shape of
  this one: pods that were already running when the Service was created keep
  serving normally, so nothing breaks until the next restart, and then the
  deployment never comes back.

- **The device plugin pod is `1/1 Running` but no GPU appears on the node.**
  Running is not advertising. Read
  `kubectl -n kube-system logs -l name=nvidia-device-plugin-ds`; `No devices
  found. Waiting indefinitely.` is the plugin telling you it found no card.
  Same cause and same fix as the first entry.
