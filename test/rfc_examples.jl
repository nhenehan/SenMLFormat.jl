# Every example of RFC 8428, read from the RFC text (JSON and CBOR here; XML and
# EXI with their codecs).

@testset "RFC examples" begin
    @testset "every JSON example is valid" begin
        exs = json_examples()
        @test length(exs) == 11
        for ex in exs
            @test !isempty(SenML.Json.decode(ex.json))
        end
    end

    @testset "the SenSML example streams record by record" begin
        # Section 5.1.2's stream "may be reported at the time it was measured":
        # feed it without the closing bracket and every record still comes out.
        ex = only(e for e in json_examples() if e.partial_stream)
        open = rstrip(rstrip(ex.json), ']')
        d = SenML.Json.StreamDecoder()
        push!(d, open)
        n = 0
        while SenML.Json.next_record!(d) !== nothing
            n += 1
        end
        @test n == 9
        @test !SenML.Json.isfinished(d)
    end

    @testset "5.1.4 is 5.1.3 resolved" begin
        resolved = resolve(example("5.1.3"))
        expected = example("5.1.4")
        @test length(resolved) == length(expected)
        for (r, e) in zip(resolved, expected)
            @test r.name == e.n
            @test r.unit == e.u
            @test r.time == e.t
            @test r.value == e.value
        end
        # And the resolved records written back are exactly section 5.1.4.
        @test Pack(to_record.(resolved)) == expected
    end

    @testset "5.1.6 mixes base names" begin
        resolved = resolve(example("5.1.6"))
        @test [r.name for r in resolved] == ["2001:db8::2/temperature", "2001:db8::2/humidity",
            "2001:db8::1/temperature", "2001:db8::1/humidity"]
        # "the last record would use the Base Name from the 3rd record but the Base
        # Time from the first record"
        @test all(r -> r.time == 1.320078429e9, resolved)
    end

    @testset "section 6 CBOR is 5.1.2 with an explicit zero time" begin
        dump = hex_dumps("6")[1]
        cbor = SenML.Cbor.decode(dump)
        json = example("5.1.2b")
        # The CBOR example writes `6: 0` on the last record; JSON omits the time.
        last = json[end]
        json[end] = Record(last.bn, last.bt, last.bu, last.bv, last.bs, last.bver, last.n,
            last.u, last.value, last.s, 0.0, last.ut, last.extensions)
        @test cbor == json
        @test SenML.Cbor.encode(json) == dump
        @test resolve(cbor; now = 1e9) == resolve(example("5.1.2b"); now = 1e9)
    end

    @testset "table 3 sizes" begin
        pack = example("5.1.3")
        # No whitespace and the smallest numbers: smaller than the RFC's 573 and 254.
        @test length(SenML.Json.encode(pack)) < 573
        @test length(SenML.Cbor.encode(pack)) <= 254
    end

    @testset "5.1.7 actuation times" begin
        now = 1_320_078_429.0
        @test [r.time for r in resolve(example("5.1.7c"); now)] == [now, now, now + 0.1, now + 0.1]
        # 5.1.7a starts with a record of base fields only.
        @test length(resolve(example("5.1.7a"); now)) == 3
    end
end
