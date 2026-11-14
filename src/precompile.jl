# A precompile workload (PrecompileTools): one small pack read and written in
# every media type, checked and resolved, so the first call in a fresh process
# does not wait for the compiler.

using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    json = """[{"bn":"urn:dev:mac:0024befffe804ff1:","bt":1.7e9,"bu":"Cel","bver":10,"n":"supply-air","u":"Cel","v":12.8},
        {"n":"room","t":-5,"v":22.6},{"n":"compressor","vb":true},{"n":"mode","vs":"cool"},
        {"n":"tag","vd":"aGkgCg"},{"n":"runtime","u":"s","s":42,"x":"ext"}]"""
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
