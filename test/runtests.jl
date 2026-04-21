using Test
using ProfilePerfetto
using JSON

@testset "ProfilePerfetto" begin
    @testset "exports" begin
        @test isdefined(ProfilePerfetto, Symbol("@profileperfetto"))
        @test isdefined(ProfilePerfetto, :profileperfetto_view)
        @test isdefined(ProfilePerfetto, :profileperfetto_open)
    end

    @testset "empty sample buffer -> valid JSON with no events" begin
        json_str = ProfilePerfetto._samples_to_perfetto_json(UInt64[], Dict())
        parsed = JSON.parse(json_str)
        @test haskey(parsed, "traceEvents")
        @test isempty(parsed["traceEvents"])
        @test parsed["metadata"]["clock-domain"] == "MONO"
    end

    @testset "_parse_samples recovers sample metadata" begin
        # Layout per sample: ips..., thread_id, task_id, cpu_cycle, sleepstate, 0, 0
        buf = UInt64[
            0x1111, 0x2222,           # ips (leaf-first)
            42,                       # thread_id
            7,                        # task_id
            1_000_000,                # timestamp_ns
            1,                        # sleepstate (awake)
            0, 0,                     # block-end marker
        ]
        samples = ProfilePerfetto._parse_samples(buf)
        @test length(samples) == 1
        s = samples[1]
        @test s.stack == UInt64[0x1111, 0x2222]
        @test s.thread_id == 42
        @test s.task_id == 7
        @test s.timestamp_ns == 1_000_000
        @test s.sleepstate == 1
    end

    @testset "profileperfetto_view returns a PerfettoDisplay" begin
        disp = profileperfetto_view(UInt64[], Dict())
        @test disp isa ProfilePerfetto.PerfettoDisplay
        @test occursin("ui.perfetto.dev", disp.html)
        # MIME rendering works
        io = IOBuffer()
        show(io, MIME"text/html"(), disp)
        @test !isempty(String(take!(io)))
    end

    @testset "@profileperfetto runs and returns a PerfettoDisplay" begin
        disp = @profileperfetto sum(sin, 1:10_000)
        @test disp isa ProfilePerfetto.PerfettoDisplay
    end
end
