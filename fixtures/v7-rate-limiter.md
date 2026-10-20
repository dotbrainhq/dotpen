---
status: in-review
agent: claude-code
updated: 2026-10-20T14:14:00
---
# Rate limiter rollout

Move the API from a fixed per-IP limit to a token bucket per API key. Ship it behind a flag and roll it out to internal keys first, then 5% of traffic.

## Steps

- [x] Add `TokenBucket` with Redis backing
- [x] Put it behind the `rate_limit_v2` flag
- [ ] Shadow mode: log every decision, block nothing
- [ ] Roll out to internal keys for one day

## Open question

Should burst size scale with the plan tier, or stay at 20 for everyone?
