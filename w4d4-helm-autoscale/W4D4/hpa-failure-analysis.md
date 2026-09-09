# HPA Failure Analysis

## 1. Where it fails
Today's setup fails right at the metric source between the Kubernetes HPA and the engine. While the HPA watches the host CPU on the node, the actual inference work is running inside the GPU cores and memory. Under our load test, `nvidia-smi` showed the GPU running hot and the vLLM batching queue backing up with waiting requests, but the container's CPU usage stayed low and flat against its assigned cores. Because the echo backend was CPU-bound, CPU usage was an honest signal there. On the real vLLM engine, the workload is strictly GPU-bound, so the scaler reads false idle signals and keeps us pinned at one replica during a traffic surge.

## 2. The signal to deploy instead
I would use engine queue depth (`vllm_num_requests_waiting`) via custom metrics. 
In LLM serving, host CPU doesn't tell you if the GPU execution queue is full. Queue depth is a direct indicator of user pain: if requests are sitting in the queue waiting for a batch slot, the inference engine is already at capacity. Watching queue depth lets the cluster add replicas before client latency spikes too hard.

## 3. Starting target and tuning
I would set an initial target of three to five waiting requests per pod. To tune this number, I would track client-side p95 latency alongside Time to First Token (TTFT). If user latency starts spiking before the HPA triggers a scale-out, I would lower the queue threshold so additional replicas spin up earlier. Conversely, if minor, temporary traffic bursts cause the cluster to scale out aggressively without actually improving user response times, I would raise the threshold to avoid wasting expensive GPU capacity.

