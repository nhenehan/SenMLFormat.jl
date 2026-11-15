# Untrusted input

This chapter covers reading SenML that comes from a network or a device you don't
control.

Every decoder is built for hostile input. It throws a `SenMLError`, and nothing
else, rather than crashing, looping forever or asking for huge amounts of memory
because of a few bad bytes:

- **Cut-off and changed input.** The tests feed every test case, cut at every
  length and changed at random, to every decoder and both stream decoders
  (`test/robustness.jl`).
- **Deep nesting.** An extension value nested very deep in JSON or CBOR is refused
  or skipped without running out of stack.
- **Huge lengths.** A CBOR array that claims 2^64 records, or a byte string that
  claims 4 GiB, fails cleanly when the input runs out.
- **XML entities.** A DTD is refused, so entity expansion ("billion laughs") can't
  happen. Only UTF-8 is accepted.
- **EXI.** The strict SenML schema allows only two levels, and EXIFormat's decoder
  limits are on.

## Checking before use

`decode` validates the pack, so what you get back follows RFC 8428's rules: one
value per record, valid names, finite numbers, a consistent version. Use
`decode_unchecked` only for input you already trust.

A valid pack can still be wrong for your application. Check the things only you
know: the names you expect, the range of each value, and whether the times make
sense.

## Limits on size

SenMLFormat reads whatever input you give it. Put a limit on the message size
before you call `decode` (CoAP and HTTP servers usually have one), or use a
`StreamDecoder` and stop when you have read enough records.
