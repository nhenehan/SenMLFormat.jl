# Your first pack

In this chapter you'll build a pack of readings, write it as JSON and read it back.

A room thermostat reports three things: the room temperature, its setpoint and how
hard the heating is working. The first record sets a base name, a base time and a
base unit, and the two records after it use them too:

```@setup first_pack
#! setup first_pack.jl
```

```@example first_pack
#! include first_pack.jl main
```

A few things to notice:

- `Record` takes keywords named after the SenML labels (`bn`, `n`, `u`, `v`, ...).
  Every field you leave out is `nothing`.
- `"heating"` sets its own unit (`/`, a ratio from 0 to 1), which beats the base
  unit for that record only.
- The JSON has no spaces, and numbers use the shortest text that reads back as
  the same value: `21` rather than `21.0`.
- `decode` gives back a `Pack` equal to the one you wrote.

## Picking the device name

SenML names should be unique around the world, so the base name usually holds a
device ID, such as a MAC address in a URN (`urn:dev:mac:...`,
[RFC 8428 section 4.5.1](https://www.rfc-editor.org/rfc/rfc8428#section-4.5.1)).
The base name and the name are joined to make the full name, here
`urn:dev:mac:0024befffe804ff1:room`. The full name may only use letters, digits
and `: . / _ -`, and must start with a letter or digit.
