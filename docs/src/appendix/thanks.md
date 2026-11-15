# Thanks

SenML is a small standard that does one job well, and SenMLFormat would not exist
without the people who wrote it and the work it stands on.

- **Cullen Jennings, Zach Shelby, Jari Arkko, Ari Keränen and Carsten Bormann**
  wrote [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428). Its examples, hex
  dumps and schema are the first tests SenMLFormat must pass.
- **Daniel Peintner** wrote [EXIficient](https://exificient.github.io/), with
  Richard Kuntschke at Siemens. SenMLFormat's EXI bytes are checked against
  EXIficient's.
- **Toralf Wittner** ([minicbor](https://crates.io/crates/minicbor)), **Yevhenii
  Reizner** ([xmlparser](https://crates.io/crates/xmlparser)) and **Gronis**
  ([nanojson](https://crates.io/crates/nanojson)) wrote the Rust parsers whose
  grammar rules SenMLFormat's own readers follow, so both libraries agree on
  every input.

Thank you.
