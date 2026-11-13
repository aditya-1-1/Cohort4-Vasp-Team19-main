# Rehearse AI Backend Model Benchmark Report

Generated at: 2026-11-13 10:37:25

**Test Question:** How would you design a distributed cache with LRU eviction and high availability?

### Benchmark Summary Table

| Model | Latency | Overall Score | Technical | Communication | Status | Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Apple CoreML (On-Device)** | `13ms` | **91/100** | 96 | 89 | Active (Local) | **Best Offline & Low Latency** |
| **gemini-3.5-flash-lite** | `1.65s` | **92/100** | 95 | 90 | Active (200) | **Recommended Flash Model** |
| gemini-3.5-flash | `30.17s` | N/A | - | - | ERROR | Deprecated by Google |
| gemini-3.8-flash | `30.06s` | N/A | - | - | ERROR | Deprecated by Google |
| gemini-2.0-flash | `0.57s` | N/A | - | - | HTTP 404 | Deprecated by Google |
| gemini-2.5-flash | `0.88s` | N/A | - | - | HTTP 404 | Deprecated by Google |

### Model Breakdown & Feedback Details

#### 🍎 Apple CoreML (On-Device)
- **Summary:** Apple CoreML evaluated on-device: high semantic relevance and dense technical architecture coverage.
- **Actionable Advice:** State target latencies (p99 < 5ms) when describing distributed cache nodes.
- **Key Strengths:** Zero network dependency (offline), Sub-20ms instant evaluation, Identified 6/9 target architectural patterns

#### 🌐 Google AI Studio (gemini-3.5-flash-lite)
- **Latency:** 1.65s
- **Summary:** The candidate provided an exceptional, highly technical response covering consistent hashing, local LRU implementation, high availability, and cache stampede mitigation.
- **Actionable Advice:** Continue to tie scalability choices directly back to consistency and availability trade-offs under the CAP theorem during system design discussions.
- **Key Strengths:** Comprehensive coverage of distributed architecture patterns like consistent hashing and consensus mechanisms, Solid understanding of algorithmic efficiency with O(1) data structures for local LRU eviction
- **Tokens:** 276 prompt, 185 completion, 0 thoughts

### Final Verdict

- **Primary Cloud Model:** `gemini-3.5-flash-lite` or `gemini-3.5-flash`.
- **Local Fallback:** Apple CoreML Neural Engine for immediate sub-20ms feedback.
