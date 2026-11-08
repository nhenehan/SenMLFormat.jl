# A precompile workload (PrecompileTools): one small pack read and written in
# every media type, checked and resolved, so the first call in a fresh process
# does not wait for the compiler.

using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    json = """[{"bn":"urn:dev:ow:10e2073a01080063:","bt":1.276020076e9,"bu":"A","bver":10,"n":"voltage","u":"V","v":120.1},
        {"n":"current","t":-5,"v":1.2},{"n":"open","vb":false},{"n":"label","vs":"Room 2"},
        {"n":"nfc","vd":"aGkgCg"},{"n":"energy","s":42,"x":"ext"}]"""
    @compile_workload begin
        pack = Json.decode(json)
        for m in instances(MediaType)
            bytes = encode(m, pack)
            decode(m, bytes)
            encode_unchecked(m, pack)
        end
        Exi.decode(Exi.encode(pack; alignment = :byte_aligned))
        resolve(pack; now = 1.7e9)
        for M in (Json, Cbor)
            d = M.StreamDecoder()
            push!(d, M === Json ? encode(SENSML_JSON, pack) : encode(SENSML_CBOR, pack))
            while M.next_record!(d) !== nothing
            end
            M.finish(d)
        end
    end
end
