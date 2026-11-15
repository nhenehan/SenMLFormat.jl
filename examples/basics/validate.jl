# Checking packs from an HVAC unit against the RFC's rules.
#
# Rust version: rsenml/examples/basics/src/bin/validate.rs.

using SenMLFormat

# ANCHOR: main
# `validate` returns nothing when the pack is good and throws a SenMLError when
# it breaks a rule. This prints which.
function check(what, pack; options...)
    try
        validate(pack; options...)
        println(what, ": ok")
    catch e
        e isa SenMLError || rethrow()
        println(what, ": ", e.kind, " (record ", e.record, ")")
    end
end

base = "urn:dev:mac:0024befffe804ff3:"
check("good pack", Pack([
    Record(bn = base, n = "supply-air", u = "Cel", v = 12.8),
    Record(n = "compressor", vb = true),
]))

# A record needs a value (or a sum).
check("no value", Pack([Record(bn = base, n = "fan")]))

# Labels ending in "_" must be understood, so an unknown one is refused.
check("unknown _ label", Pack([Record(bn = base, n = "fan", v = 0.65,
                                      extensions = ["mode_" => "eco"])]))

# "RPM" is not in the SenML units registry. RFC 8428 allows it, unless you ask
# for registered units only.
rpm = Pack([Record(bn = base, n = "fan-speed", u = "RPM", v = 900)])
check("RPM", rpm)
check("RPM, registered units only", rpm; registered_units = true)
# ANCHOR_END: main
