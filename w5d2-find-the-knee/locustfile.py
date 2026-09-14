# Week-5 load for the knee ramp. Same request shape as the W4D4 HPA lab, plus
# the one thing that changed on Thursday: the service is keyed.
#
#   kubectl port-forward svc/team-serving 8000:8000 &
#   export AIDC_API_KEY=$(kubectl get secret serving-keys \
#       -o jsonpath='{.data.api-key}' | base64 -d)
#   locust -f locustfile.py --headless -u 8 -r 8 -t 40s \
#       -H http://127.0.0.1:8000 --only-summary
#
# Why this file exists rather than reusing W4D4's: that one predates go-live and
# sends no Authorization header. Against a keyed release every request comes
# back 401 in about a quarter of a millisecond, and nothing on your dashboard
# says so, because the availability panel counts 5xx and a 401 is 4xx. You would
# read a beautiful 100%-available, 5 ms-p95, high-throughput service and call it
# your knee. The preflight below exists to make that impossible.
import os
import sys

import requests
from locust import HttpUser, between, events, task

API_KEY = os.environ.get("AIDC_API_KEY", "")

# The prompt is what makes the echo backend spend CPU; keep it if you want the
# knee to be about the service rather than about your network.
BODY = {
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role": "user", "content": "repeat the word load " * 60}],
    "max_tokens": 200,
}


def _headers():
    return {"Authorization": "Bearer " + API_KEY} if API_KEY else {}


@events.test_start.add_listener
def _preflight(environment, **_kwargs):
    """One real request before any load, so a ramp cannot measure rejections.

    A ramp that 401s produces clean-looking numbers on every panel you are
    about to read, so this refuses to start rather than letting you spend the
    morning measuring your own auth failures.
    """
    host = (environment.host or "").rstrip("/")
    try:
        r = requests.post(host + "/v1/chat/completions", json=BODY,
                          headers=_headers(), timeout=30)
    except Exception as exc:  # noqa: BLE001 - any transport failure is fatal here
        print("\nPREFLIGHT FAILED: cannot reach %s (%s)\n"
              "Is the port-forward up?  kubectl port-forward svc/team-serving 8000:8000 &\n"
              % (host, exc), file=sys.stderr)
        environment.runner.quit()
        return

    if r.status_code == 401:
        print("\nPREFLIGHT FAILED: the service answered 401.\n"
              "Your release has been keyed since Thursday's go-live, and this ramp\n"
              "sent %s. Export the key and run again:\n\n"
              "  export AIDC_API_KEY=$(kubectl get secret serving-keys \\\n"
              "      -o jsonpath='{.data.api-key}' | base64 -d)\n\n"
              "Refusing to start: a 401 ramp reads as 100%% available with a 5 ms p95,\n"
              "and every number you took from it would be wrong.\n"
              % ("no key" if not API_KEY else "a key the service rejected"),
              file=sys.stderr)
        environment.runner.quit()
        return

    if r.status_code != 200:
        print("\nPREFLIGHT FAILED: the service answered %d, not 200.\n"
              "Fix the service before measuring it; a ramp against a broken\n"
              "release measures the breakage.\n" % r.status_code, file=sys.stderr)
        environment.runner.quit()
        return

    print("preflight ok: %s answered 200 %s"
          % (host, "with your key" if API_KEY else "(service is open, no key set)"))


class ChatUser(HttpUser):
    wait_time = between(0.05, 0.2)

    def on_start(self):
        self.client.headers.update(_headers())

    @task
    def chat(self):
        self.client.post("/v1/chat/completions", json=BODY,
                         name="/v1/chat/completions")
