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
| JSON | decode | 2.5 | 9.5 | 3.9× |
| JSON | encode | 2.0 | 3.9 | 2.0× |
| JSON | decode+resolve | 3.3 | 8.5 | 2.6× |
| CBOR | decode | 1.6 | 3.6 | 2.3× |
| CBOR | encode | 1.0 | 1.7 | 1.7× |
| XML | decode | 3.7 | 11.2 | 3.1× |
| XML | encode | 1.8 | 4.0 | 2.2× |
| EXI bit-packed | decode | 4.8 | 15.9 | 3.3× |
| EXI bit-packed | encode | 3.3 | 5.9 | 1.8× |
| EXI byte-aligned | decode | 5.0 | 16.1 | 3.2× |
| EXI byte-aligned | encode | 3.5 | 6.2 | 1.8× |

## synthetic 200: time per call in µs

| Codec | Operation | rsenml | SenML.jl | SenML.jl / rsenml |
|---|---|---:|---:|---:|
| JSON | decode | 60.0 | 115.8 | 1.9× |
| JSON | encode | 35.5 | 72.0 | 2.0× |
| JSON | decode+resolve | 77.9 | 157.1 | 2.0× |
| CBOR | decode | 28.0 | 59.0 | 2.1× |
| CBOR | encode | 15.7 | 33.2 | 2.1× |
| XML | decode | 63.5 | 190.4 | 3.0× |
| XML | encode | 43.0 | 109.1 | 2.5× |
| EXI bit-packed | decode | 78.4 | 245.6 | 3.1× |
| EXI bit-packed | encode | 43.6 | 98.0 | 2.2× |
| EXI byte-aligned | decode | 78.2 | 242.6 | 3.1× |
| EXI byte-aligned | encode | 41.7 | 92.7 | 2.2× |
