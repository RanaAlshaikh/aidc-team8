# Capacity and cost worksheet: <team name>, W5D2

## Ramp (from the dashboard, during each level's window)

| users | req/min | p95 ms |
|---|---|---|
| 2 | <n> | <n> |
| 4 | <n> | <n> |
| 8 | <n> | <n> |
| 16 | <n> | <n> |
| 32 | <n> | <n> |

## The knee

- Published p95 SLO: <n> ms
- Knee: users=<n>, rate=<n> req/min, p95=<n> ms  (or a range: <n>-<n> users)
- Max honest rate at our SLO: <n> req/min per replica

## Replicas for targets

- 2x knee load (<n> req/min): ceil(<n>/<n>) = <n> replicas
- 3x knee load (<n> req/min): ceil(<n>/<n>) = <n> replicas
- Current HPA maxReplicas 3: sufficient up to <n> req/min; we would raise it to <n> for 3x

## Cost (assumed replica-hour rate: $<n>/h; ~200 tokens/request)

- Tokens/hour at the knee: <n> req/min x 60 x 200 = <n>
- Cost per million tokens, steady knee: $<n>
- Double load, 2 replicas: $<n> per million (same per-token, twice the bill: <n>)
- Spiky (2x for 4h/day, knee otherwise), fixed 2 replicas all day: $<n> per million blended
- Spiky with autoscaling (2nd replica only 4h): $<n> per million blended
- One sentence: what utilisation did to the last two numbers.

## Procurement (shapes priced with YOUR knee as the unit)

Shapes: A small $0.50/h = 1 unit, autoscales; B big $1.60/h = 4 units, one
box; C burst $0.30/h = 0.6 unit sustained, bursts to 1 briefly.

- Steady 4 units all day - cheapest shape: <shape>, daily bill $<n>, against
  the runner-up's $<n>
- Spiky (peak 4 units for 2h, mean 1) - chosen shape: <shape>, blended daily
  bill $<n>, and why the big box loses here: <one sentence on utilisation>
- The line the sheet does not price: <one sentence on blast radius or surge
  headroom for the shape you chose>

<signed by the team>
