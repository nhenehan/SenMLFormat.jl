# SenML.jl and rsenml: performance

Written by `bench/run.sh`; do not edit by hand.

SenML.jl is compared with rsenml only. Both read the same JSON files
(`bench/data`): the RFC 8428 section 5.1.3 example and the 200-record synthetic
pack of rsenml's `compare` (resolved records: three numeric sensors and a door
switch, 30 s apart). Both are timed the same way (`median_ns` of rsenml's
`compare/src/perf.rs`): calls batched to at least 200 µs, the median of 51
batches after 20 warm-up calls. `bench/run.sh` runs both three times, taking
turns, and keeps the fastest median of each cell. Decoders validate and encoders validate first,
as `decode` and `encode` do. "decode+resolve" is JSON decode, then resolution with
a given "now".

- CPU: AMD Ryzen 7 7840U w/ Radeon 780M Graphics
- Julia: 1.12.7 (default flags)
- rsenml: v0.9.1, rustc 1.99.0 (b940084d7 2026-09-28), release profile with LTO, one codegen unit

## Sizes in bytes

| Codec | RFC 5.1.3 (22 records) | synthetic 200 |
|---|---:|---:|
| JSON | 401 (equal) | 14423 (equal) |
| CBOR | 245 (equal) | 10446 (equal) |
| XML | 510 (equal) | 14976 (equal) |
| EXI bit-packed | 161 (equal) | 2486 (equal) |
| EXI byte-aligned | 251 (equal) | 4146 (equal) |

## RFC 5.1.3 (22 records): time per call in µs

| Codec | Operation | rsenml | SenML.jl | SenML.jl / rsenml |
|---|---|---:|---:|---:|
| JSON | decode | 2.7 | 16.1 | 6.0× |
| JSON | encode | 2.0 | 26.1 | 12.9× |
| JSON | decode+resolve | 3.8 | 22.8 | 6.1× |
| CBOR | decode | 1.5 | 10.2 | 6.6× |
| CBOR | encode | 1.0 | 22.5 | 23.3× |
| XML | decode | 3.5 | 17.5 | 5.0× |
| XML | encode | 1.8 | 26.9 | 14.6× |
| EXI bit-packed | decode | 5.1 | 22.0 | 4.3× |
| EXI bit-packed | encode | 3.3 | 40.0 | 12.0× |
| EXI byte-aligned | decode | 5.6 | 22.9 | 4.1× |
| EXI byte-aligned | encode | 3.8 | 39.9 | 10.4× |

## synthetic 200: time per call in µs

| Codec | Operation | rsenml | SenML.jl | SenML.jl / rsenml |
|---|---|---:|---:|---:|
| JSON | decode | 56.9 | 228.2 | 4.0× |
| JSON | encode | 38.8 | 437.9 | 11.3× |
| JSON | decode+resolve | 80.2 | 352.4 | 4.4× |
| CBOR | decode | 29.6 | 151.1 | 5.1× |
| CBOR | encode | 15.8 | 388.7 | 24.6× |
| XML | decode | 70.7 | 319.1 | 4.5× |
| XML | encode | 43.0 | 431.3 | 10.0× |
| EXI bit-packed | decode | 85.9 | 358.2 | 4.2× |
| EXI bit-packed | encode | 44.4 | 645.8 | 14.6× |
| EXI byte-aligned | decode | 84.5 | 365.8 | 4.3× |
| EXI byte-aligned | encode | 42.6 | 638.5 | 15.0× |
