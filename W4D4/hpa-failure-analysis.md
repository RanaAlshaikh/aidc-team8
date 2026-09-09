# HPA Failure Analysis

The current HPA scales based on CPU utilization. This works for the CPU test service, but it can fail on the real vLLM engine because the workload is GPU-bound. The GPU and request queue can be busy while CPU utilization remains low, so CPU does not accurately represent how overloaded the inference engine is.

I would use **engine queue depth (`vllm_num_requests_waiting`)** instead. For our workload, many users may send inference requests at the same time, so the number of requests waiting is a direct indication that the engine cannot serve requests fast enough.

I would start with a target of **5 waiting requests per replica**. I would then monitor request latency, queue depth, GPU utilization, and replica count. If latency or the queue remains high, I would lower the target so scaling happens earlier. If replicas scale too aggressively while latency remains acceptable, I would increase the target.
