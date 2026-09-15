Sizing a saudi data centre
AI Data Center Bootcamp · Week 5 · Day 3 · team 8 case study · Tuesday 15 September 2026

Site: HUMAIN Dammam: up to 100 MW to start, on land for ten 200 MW buildings 
Power: PUE 1.25; 10% of IT for switches and storage; 20% headroom.
Racks: a DGX H100 node is 8 GPUs, 640 GB, 10.2 kW, four to a rack. A GB300 NVL72 rack is 72
GPUs, about 20 TB, about 120 kW.
Serving: a model's weights at fp8, plus context for 32 conversations of 128K tokens.
Training: 6 operations per parameter per token, 20 tokens per parameter, 40% of peak. An H100
peaks at 989 TFLOPS.
Bill: the site draws 65% of its connection on average; USD 0.08 per kWh (30 halalas), or 0.048 at
the industrial band.
Cost: 125 output tokens per second per GPU; USD 450,000 per MW per month for everything but
electricity.


____________________________________________________________________________________________________________________________________________

1- How many racks and GPUs does the site's power buy?

PUE = 1.25
Power = 100 MW 

IT Power =100/1.25=80MW
remove 10% for switches : 80x0.10 = 8MW 
then 80 - 8 = 72 MW 

keep 20% headroom : 72x0.20 = 14.4MW 
then computer power 72 - 14.4 = 57.6 MW 

convert power to H100 nodes giving  8 H100 GPUs/node ,  10.2kW/node and 4 nodes/rack so:   57,6 MW =  57.600 kW 
Nodes = 57.600 / 10.2 = 5,647
GPUs = 5,647 x 8 = 45,176 H100s
Racks = 5647 / 4= 1,412 

Answer: 57.6 MW compute power , 5.647 H100 nodes , 45,176 H100 GPUs and about 1,412 racks

____________________________________________________________________________________________________________________________________________

2- What is the largest open model it can serve, and how many copies of it? 

Model: Llama 3.1 405B 
Weights, fp8: 405B × 1 byte = 405 GB
KV cache: 32 conversations × 128K tokens = 4,194,304 tokens
 2 × 126 layers × 8 KV heads × 128 head_dim × 1 byte = 258,048 bytes/token
 258,048 × 4,194,304 ≈ 1,082 GB
Total: ~1.49 TB/copy

GPUs per copy:
H100: 640 GB / 8 GPUs = 80 GB/GPU 
1.49 TB ÷ 80 GB = 18.6  ≈ 19 GPUs 

Copies per rack:
Rack = 4 node * 8 GPUs = 32 GPUs 
32 ÷ 19 = 1.68 → 1 copy/rack 
so for check 
19 × 80 GB = 1,520 GB > 1.49 TB
total: 1,412 racks × 1 = 1,412 copies 
____________________________________________________________________________________________________________________________________________

3- What is the largest model it could train in six months? 

Compute = 6 × N × 20N = 120N² 
Total six-month compute: 
45,176 × (989 TFLOPS × 40%) × 15.8M 
seconds ≈ 2.82 × 10^26 operations. 
120N² = 2.82 × 10^26 N ≈ 1.53 trillion parameters. 
Training tokens ≈ 20N ≈ 30.7 trillion tokens. 

1.53T parameter model on ~30.7T tokens, assuming ideal cluster scaling beyond the stated 40% peak factor. 

____________________________________________________________________________________________________________________________________________

4- What is its electricity bill for a month?

Capacity: 100MW (100,00kW)
Average power draw = 65% of 100MW = 65 MW (65,000kW)
Monthly energy consumption ( 30 days / 720h):
                   65,000kW X 720 = 46,800,000 kWh (46.8 GWh) 
            In USD: 46,800,000 kWh * $0.08/kWh  = $3,744,000 
            In SAR: 46,800,000 kWh × 30 halala/kWh = 1,404,000,000 halala
                   1,404,000,000 ÷100 = 14,040,000  riyal
____________________________________________________________________________________________________________________________________________

5- What does a million tokens cost, at 30% and at 80% of capacity sold? 

100 MW × $450,000/MW = $45,000,000 
Electricity (from Q4): $3,744,000 
Total: $48,744,000/month 
In SAR (×3.75): SAR 182,790,000/month 

GPUs (from Q1): 45,176 
45,176 * 125 tokens/s/GPU = 5,647,000 tokens/s 
5,647,000 tokens/s * 2,592,000 s/month (30 × 24 × 3600) = ~14.64 trillion tokens/month 

At 30%:
Tokens = 0.3 × 14.64T = 4.39T tokens = 4,392,000 million tokens
Cost/million
USD: $48,744,000 ÷ 4,392,000 ≈ $11.10/M tokens
SAR: 182,790,000 ÷ 4,392,000 ≈ SAR 41.61/M tokens 
 
At 80%:
Tokens = 0.8 × 14.64T = 11.71T tokens = 11,712,000 million tokens
USD: $48,744,000 ÷ 11,712,000 ≈ $4.16/M tokens
SAR: 182,790,000 ÷ 11,712,000 ≈ SAR 15.61/M tokens
____________________________________________________________________________________________________________________________________________
