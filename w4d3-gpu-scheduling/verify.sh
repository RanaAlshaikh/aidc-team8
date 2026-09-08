#!/usr/bin/env bash
# Green check for W4D3 (GPU scheduling as accounting).
# Run in this directory:  bash verify.sh
# Prints exactly one line last: GREEN CHECK: PASS  or  GREEN CHECK: FAIL (<reason>)
#
# Two different clusters reach this file, so it checks two different things.
#
# Tier 0 (kind, no GPU): the serving deployment's live ledger entry, then the
# GPU-overdraft experiment performed by the script itself, because a pod that
# asks for a resource no node advertises must go Pending with a scheduler event
# that names it.
#
# Tier 1 (the team pod, GPU real): that experiment inverts, so instead it checks
# what actually goes wrong there. Every assertion below corresponds to a fault
# reproduced on real hardware; see instructor/tier1-pod-runbook.md.
set -u

DOOMED=""
cleanup() { [ -n "$DOOMED" ] && kubectl delete pod "$DOOMED" --ignore-not-found >/dev/null 2>&1; }
trap cleanup EXIT
fail() { echo "GREEN CHECK: FAIL ($1)"; exit 1; }

command -v kubectl >/dev/null || fail "kubectl not on PATH"

gpu=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.nvidia\.com/gpu}' 2>/dev/null)

# ---------------------------------------------------------------- tier 1 ----
if printf '%s' "$gpu" | grep -q '[1-9]'; then
  DEPLOY="${DEPLOY:-vllm}"
  kubectl get deployment "$DEPLOY" >/dev/null 2>&1 \
    || fail "GPU node, but no deployment '$DEPLOY'; apply vllm-gpu.yaml"

  # A GPU alone leaves the pod BestEffort: QoS is computed from cpu and memory
  # only. The engine must carry all three or it is first in line to be throttled.
  for res in cpu memory 'nvidia\.com/gpu'; do
    v=$(kubectl get deployment "$DEPLOY" -o jsonpath="{.spec.template.spec.containers[0].resources.requests.$res}")
    [ -n "$v" ] || fail "the engine requests no ${res//\\/}; it cannot hold a ledger entry it never made"
  done

  pod=$(kubectl get pods -l app=vllm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -n "$pod" ] || fail "no pod with label app=vllm"

  qos=$(kubectl get pod "$pod" -o jsonpath='{.status.qosClass}')
  [ "$qos" = "Guaranteed" ] \
    || fail "engine QoS is $qos, not Guaranteed; requests must equal limits on cpu and memory"

  # A Service named `vllm` injects VLLM_PORT=tcp://... into every pod in the
  # namespace, which vLLM parses as its own port and dies on. Pods that predate
  # the Service keep running, so this only bites at the next restart.
  kubectl get svc vllm >/dev/null 2>&1 \
    && fail "a Service named 'vllm' exists; it sets VLLM_PORT and kills the engine on next restart"

  kubectl get pod "$pod" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True \
    || fail "engine pod is not Ready; check kubectl logs $pod"

  # The decisive one: the scheduler debits a GPU whether or not the container
  # ever receives it. Only the container can answer.
  kubectl exec "$pod" -- nvidia-smi -L >/dev/null 2>&1 \
    || fail "the container cannot see the GPU it was charged for; node was not provisioned per the pod runbook"

  echo "tier 1: engine Guaranteed, GPU visible inside the container, Service name safe"
  echo "GREEN CHECK: PASS"
  exit 0
fi

# ---------------------------------------------------------------- tier 0 ----
DEPLOY="${DEPLOY:-serving}"
kubectl get deployment "$DEPLOY" >/dev/null 2>&1 || fail "no deployment '$DEPLOY'"

spec=$(kubectl get deployment "$DEPLOY" -o json)
for want in requests limits; do
  printf '%s' "$spec" | grep -q "\"$want\"" || fail "serving spec has no $want; Step 1 not applied"
done
for res in cpu memory; do
  v=$(kubectl get deployment "$DEPLOY" -o jsonpath="{.spec.template.spec.containers[0].resources.requests.$res}")
  [ -n "$v" ] || fail "serving requests carry no $res"
done

image=$(kubectl get deployment "$DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')
DOOMED="verify-wants-gpu-$$"
cat <<EOF | kubectl apply -f - >/dev/null || fail "could not create the doomed GPU pod"
apiVersion: v1
kind: Pod
metadata:
  name: $DOOMED
spec:
  containers:
    - name: wisher
      image: $image
      command: ["sleep", "60"]
      resources:
        requests: {nvidia.com/gpu: 1}
        limits: {nvidia.com/gpu: 1}
EOF

verdict=""
for _ in $(seq 1 20); do
  phase=$(kubectl get pod "$DOOMED" -o jsonpath='{.status.phase}' 2>/dev/null)
  events=$(kubectl get events --field-selector "involvedObject.name=$DOOMED" -o jsonpath='{.items[*].message}' 2>/dev/null)
  if printf '%s' "$events" | grep -qi 'nvidia.com/gpu'; then verdict=ok; break; fi
  [ "$phase" = "Running" ] && fail "the GPU pod scheduled on a node with no GPU; something is very wrong"
  sleep 1
done
[ "$verdict" = "ok" ] || fail "no scheduler event naming nvidia.com/gpu appeared for the Pending pod"

phase=$(kubectl get pod "$DOOMED" -o jsonpath='{.status.phase}')
[ "$phase" = "Pending" ] || fail "doomed pod is $phase, expected Pending"

echo "overdraft verified: Pending with 'Insufficient nvidia.com/gpu'"
echo "GREEN CHECK: PASS"
