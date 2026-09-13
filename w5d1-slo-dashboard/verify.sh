#!/usr/bin/env bash
# Green check for W5D1 (SLO dashboard).
# Run in this directory:  bash verify.sh
# Prints exactly one line last: GREEN CHECK: PASS  or  GREEN CHECK: FAIL (<reason>)
set -u
PORT=13444; PF_PID=""
fail() { echo "GREEN CHECK: FAIL ($1)"; [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null; exit 1; }

command -v kubectl >/dev/null || fail "kubectl not on PATH"
kubectl get deployment grafana >/dev/null 2>&1 || fail "no grafana deployment (Step 1)"
kubectl port-forward svc/grafana "$PORT:3000" >/dev/null 2>&1 & PF_PID=$!
up=""; for _ in $(seq 1 20); do curl -sf "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && { up=1; break; }; sleep 0.5; done
[ -n "$up" ] || fail "grafana never answered /api/health"

# find the team dashboard by EXACT title, then pull it. Grafana's search is a
# substring match, so a loose check here would happily accept the shipped
# reference solution and pass a team that built nothing.
uid=$(curl -s "http://127.0.0.1:$PORT/api/search?query=Team%20SLOs" | python3 -c "
import json,sys
r=json.load(sys.stdin)
hits=[x for x in r if x.get('title','').strip()=='Team SLOs']
print(hits[0]['uid'] if hits else '')")
[ -n "$uid" ] || fail "no dashboard titled exactly 'Team SLOs' (Step 3: save it with that name; the reference solution does not count)"

curl -s "http://127.0.0.1:$PORT/api/dashboards/uid/$uid" > /tmp/slo-dash-$$.json
python3 - /tmp/slo-dash-$$.json <<'PY' || { rm -f /tmp/slo-dash-$$.json; fail "dashboard shape check failed (see line above)"; }
import json, sys
d = json.load(open(sys.argv[1]))["dashboard"]
panels = d.get("panels", [])
stats = [p for p in panels if p.get("type") == "stat"]
series = [p for p in panels if p.get("type") == "timeseries"]
if len(stats) < 4:
    print(f"only {len(stats)} stat panels; the four SLIs each need one"); sys.exit(1)
if not series:
    print("no timeseries panel; latency percentiles need one"); sys.exit(1)
exprs = json.dumps(panels)
for need, why in [("histogram_quantile", "a p95 needs histogram_quantile"),
                  ("aidc_requests_total", "availability/error panels read aidc_requests_total"),
                  ('5..', "the 5xx matcher is missing")]:
    if need not in exprs:
        print(f"{why}"); sys.exit(1)

# Step 3 makes the description field the rule: every panel states the question
# it answers, and D5's readiness review asks a reviewer to read one off the
# screen. A rule nothing checks is a suggestion.
blank = [p.get("title") or "(untitled)" for p in panels
         if not (p.get("description") or "").strip()]
if blank:
    print("no description on: " + ", ".join(blank)
          + " (Step 3: one line naming the question each panel answers)")
    sys.exit(1)
PY
rm -f /tmp/slo-dash-$$.json

# the availability query must actually answer through grafana's proxy
val=$(curl -s "http://127.0.0.1:$PORT/api/datasources/proxy/uid/prom/api/v1/query" \
  --data-urlencode 'query=100 * (1 - (sum(rate(aidc_requests_total{route="/v1/chat/completions",code=~"5.."}[1h])) or vector(0)) / clamp_min(sum(rate(aidc_requests_total{route="/v1/chat/completions"}[1h])), 1e-9))' \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else '')")
[ -n "$val" ] || fail "the availability query returns nothing through the datasource; is the scrape running?"
echo "availability over the last hour: ${val}%"
kill "$PF_PID" 2>/dev/null; PF_PID=""

[ -f my-slo-targets.md ] || fail "no my-slo-targets.md (copy slo-targets.md, fill it, save as my-slo-targets.md)"
grep -qE '<[a-zA-Z.][^>]*>' my-slo-targets.md && fail "my-slo-targets.md still has angle-bracket placeholders"
grep -qE '[0-9]' my-slo-targets.md || fail "my-slo-targets.md carries no numbers"

echo "GREEN CHECK: PASS"
