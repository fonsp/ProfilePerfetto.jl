using Test
using ProfilePerfetto
using JSON

@testset "ProfilePerfetto" begin
    @testset "exports" begin
        @test isdefined(ProfilePerfetto, Symbol("@perfetto"))
        @test isdefined(ProfilePerfetto, :perfetto_view)
        @test isdefined(ProfilePerfetto, :perfetto_open)
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
            1_000_000,                # timestamp_ticks
            1,                        # sleepstate (awake)
            0, 0,                     # block-end marker
        ]
        samples = ProfilePerfetto._parse_samples(buf)
        @test length(samples) == 1
        s = samples[1]
        @test s.stack == UInt64[0x1111, 0x2222]
        @test s.thread_id == 42
        @test s.task_id == 7
        @test s.timestamp_ticks == 1_000_000
        @test s.sleepstate == 1
    end

    @testset "perfetto_view returns a PerfettoDisplay" begin
        disp = perfetto_view(UInt64[], Dict())
        @test disp isa ProfilePerfetto.PerfettoDisplay
        @test occursin("ui.perfetto.dev", disp.html)
        # MIME rendering works
        io = IOBuffer()
        show(io, MIME"text/html"(), disp)
        @test !isempty(String(take!(io)))
    end

    @testset "@perfetto runs and returns a PerfettoDisplay" begin
        disp = @perfetto sum(sin, 1:10_000) max_rounds=1
        @test disp isa ProfilePerfetto.PerfettoDisplay
    end

    @testset "@perfetto accepts kwargs" begin
        # Multiple kwargs forwarded to _autocalibrate
        disp2 = @perfetto sum(sin, 1:10_000) max_rounds=2 min_delay=1e-4 initial_delay=0.01
        @test disp2 isa ProfilePerfetto.PerfettoDisplay

        # kwargs values are evaluated in caller scope
        local_rounds = 1
        disp3 = @perfetto sum(sin, 1:10_000) max_rounds=local_rounds
        @test disp3 isa ProfilePerfetto.PerfettoDisplay

        # Non-`key = value` trailing arg is rejected at macro expansion
        @test_throws Exception @eval @perfetto sum(sin, 1:10_000) 42
    end
end
