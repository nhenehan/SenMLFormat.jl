//! Times rsenml on the datasets in a directory and prints one TSV line per
//! (dataset, codec, operation): the median time of one call in nanoseconds.
//! The method is rsenml compare's `median_ns`.

use std::hint::black_box;
use std::time::{Duration, Instant};

use rsenml::exi::{Alignment, EncodeOptions};
use rsenml::{cbor, exi, json, xml};

/// Median time of one call: calls are batched so one sample lasts at least
/// 200 µs; 51 samples after 20 warm-up calls.
fn median_ns(mut f: impl FnMut()) -> f64 {
    for _ in 0..20 {
        f();
    }
    let mut batch = 1u32;
    loop {
        let t = Instant::now();
        for _ in 0..batch {
            f();
        }
        if t.elapsed() >= Duration::from_micros(200) || batch >= 1 << 20 {
            break;
        }
        batch *= 2;
    }
    let mut samples: Vec<f64> = (0..51)
        .map(|_| {
            let t = Instant::now();
            for _ in 0..batch {
                f();
            }
            t.elapsed().as_nanos() as f64 / f64::from(batch)
        })
        .collect();
    samples.sort_by(f64::total_cmp);
    samples[samples.len() / 2]
}

fn main() {
    let dir = std::env::args().nth(1).expect("usage: senml-jl-bench-rsenml DATA_DIR");
    let ba = EncodeOptions::new().with_alignment(Alignment::ByteAligned);
    for set in ["rfc-5.1.3", "synthetic-200"] {
        let text = std::fs::read(format!("{dir}/{set}.json")).expect("dataset");
        let pack = json::decode(&text).expect("valid dataset");
        let line = |codec: &str, op: &str, ns: f64| println!("{set}\t{codec}\t{op}\t{ns:.1}");

        let b = json::encode(&pack).unwrap();
        line("JSON", "size", b.len() as f64);
        line("JSON", "decode", median_ns(|| { let _ = black_box(json::decode(black_box(&b))); }));
        line("JSON", "encode", median_ns(|| { let _ = black_box(json::encode(black_box(&pack))); }));
        line("JSON", "decode+resolve", median_ns(|| {
            let p = json::decode(black_box(&b));
            let _ = black_box(p.map(|p| p.resolve(Some(1_700_000_000.0)).map(|r| r.len())));
        }));

        let b = cbor::encode(&pack).unwrap();
        line("CBOR", "size", b.len() as f64);
        line("CBOR", "decode", median_ns(|| { let _ = black_box(cbor::decode(black_box(&b))); }));
        line("CBOR", "encode", median_ns(|| { let _ = black_box(cbor::encode(black_box(&pack))); }));

        let b = xml::encode(&pack).unwrap();
        line("XML", "size", b.len() as f64);
        line("XML", "decode", median_ns(|| { let _ = black_box(xml::decode(black_box(&b))); }));
        line("XML", "encode", median_ns(|| { let _ = black_box(xml::encode(black_box(&pack))); }));

        let b = exi::encode(&pack).unwrap();
        line("EXI bit-packed", "size", b.len() as f64);
        line("EXI bit-packed", "decode", median_ns(|| { let _ = black_box(exi::decode(black_box(&b))); }));
        line("EXI bit-packed", "encode", median_ns(|| { let _ = black_box(exi::encode(black_box(&pack))); }));

        let b = exi::encode_with(&pack, &ba).unwrap();
        line("EXI byte-aligned", "size", b.len() as f64);
        line("EXI byte-aligned", "decode", median_ns(|| { let _ = black_box(exi::decode(black_box(&b))); }));
        line("EXI byte-aligned", "encode", median_ns(|| { let _ = black_box(exi::encode_with(black_box(&pack), &ba)); }));
    }
}
