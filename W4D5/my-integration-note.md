# Integration note: team 14 (v1, go-live)

- **base_url** `https://t14.aidc.nadir.sh/v1`
- **service root** `https://t14.aidc.nadir.sh`
- **model id:** `Qwen/Qwen2.5-1.5B-Instruct-AWQ`
- **auth:** bearer key, handed over DM to our on-call
- **modalities:** text in, text out, tool calls per the OpenAI schema using the Hermes tool-call parser; function-calling smoke score 10/10 .
- **example call:**
  ```bash
  curl -s "https://t14.aidc.nadir.sh/v1/chat/completions" \
    -H "Authorization: Bearer REDACTED" \
    -H "Content-Type: application/json" \
    -d '{"model":"Qwen/Qwen2.5-1.5B-Instruct-AWQ","messages":[{"role":"user","content":"hello from outside"}]}'
- **SLOs we publish:**  availability 99% over the go-live window · TTFT p95 < 1500 ms · error rate < 1%
- **limits, declared honestly:** max_tokens clamp 128 · concurrency knee approximately 8  · maximum model context 4096 tokens · text input/output only
- **on-call:** Rna0.0· Discord· response within 10 minutes during the window
