# References

## Standards

| Standard | Reference | Used for |
|---|---|---|
| [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428) | Cullen Jennings, Zach Shelby, Jari Arkko, Ari Keränen, and Carsten Bormann. 2018. Sensor Measurement Lists (SenML). RFC 8428. RFC Editor. https://doi.org/10.17487/RFC8428 | Everything (implemented) |
| [RFC 9100](https://www.rfc-editor.org/rfc/rfc9100) | Carsten Bormann. 2021. Sensor Measurement Lists (SenML) Features and Versions. RFC 9100. RFC Editor. https://doi.org/10.17487/RFC9100 | Updates RFC 8428's `bver` (not implemented) |
| [RFC 8798](https://www.rfc-editor.org/rfc/rfc8798) | Carsten Bormann. 2020. Additional Units for Sensor Measurement Lists (SenML). RFC 8798. RFC Editor. https://doi.org/10.17487/RFC8798 | More units (not implemented) |
| [RFC 9193](https://www.rfc-editor.org/rfc/rfc9193) | Ari Keränen and Carsten Bormann. 2022. Sensor Measurement Lists (SenML) Fields for Indicating Data Value Content-Format. RFC 9193. RFC Editor. https://doi.org/10.17487/RFC9193 | `ct` and `ce` fields (not implemented); its section 8 on CBOR text keys |
| [RFC 8790](https://www.rfc-editor.org/rfc/rfc8790) | Ari Keränen and Mojan Mohajer. 2020. FETCH and PATCH with Sensor Measurement Lists (SenML). RFC 8790. RFC Editor. https://doi.org/10.17487/RFC8790 | Not implemented |
| [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) | Tim Bray (Ed.). 2017. The JavaScript Object Notation (JSON) Data Interchange Format. RFC 8259. RFC Editor. https://doi.org/10.17487/RFC8259 | JSON |
| [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) | Carsten Bormann and Paul Hoffman. 2020. Concise Binary Object Representation (CBOR). RFC 8949. RFC Editor. https://doi.org/10.17487/RFC8949 | CBOR |
| [EXI 1.0](https://www.w3.org/TR/exi/) | John Schneider, Takuki Kamiya, Daniel Peintner, and Rumen Kyusakov (Eds.). 2014. Efficient XML Interchange (EXI) Format 1.0 (Second Edition). W3C Recommendation. https://www.w3.org/TR/2014/REC-exi-20140211/ | EXI |
| [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648) | Simon Josefsson. 2006. The Base16, Base32, and Base64 Data Encodings. RFC 4648. RFC Editor. https://doi.org/10.17487/RFC4648 | base64url data values |
| [RFC 7252](https://www.rfc-editor.org/rfc/rfc7252) | Zach Shelby, Klaus Hartke, and Carsten Bormann. 2014. The Constrained Application Protocol (CoAP). RFC 7252. RFC Editor. https://doi.org/10.17487/RFC7252 | Content-Format numbers |

## Implementations

| Implementation | Language | Role here |
|---|---|---|
| [rsenml](https://github.com/nhenehan/rsenml) | Rust | The library SenMLFormat is ported from; the source of the test data |
| [EXIFormat](https://github.com/nhenehan/EXIFormat.jl) | Julia | The EXI codec under `SenMLFormat.Exi` |
| [EXIficient](https://github.com/EXIficient/exificient) | Java | Reference EXI bytes (`test/fixtures/exificient`) |
| [nanojson](https://crates.io/crates/nanojson), [minicbor](https://crates.io/crates/minicbor), [xmlparser](https://crates.io/crates/xmlparser) | Rust | rsenml's parsers, whose grammar rules SenMLFormat's own readers follow |
