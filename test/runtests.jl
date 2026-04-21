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
        disp = @perfetto sum(sin, 1:10_000)
        @test disp isa ProfilePerfetto.PerfettoDisplay
    end

    @testset "GC events appear in JSON as X slices on the GC track" begin
        gc_events = [
            ProfilePerfetto.GCEvent(1_000_000, 1_500_000, false, 1),
            ProfilePerfetto.GCEvent(2_000_000, 3_200_000, true, 2),
        ]
        json_str = ProfilePerfetto._samples_to_perfetto_json(
            UInt64[], Dict(); gc_events = gc_events,
        )
        parsed = JSON.parse(json_str)
        slices = [e for e in parsed["traceEvents"] if get(e, "ph", "") == "X"]
        @test length(slices) == 2
        @test all(e -> e["tid"] == 0 && e["pid"] == 1, slices)
        # Normalized relative to the earliest GC event's start_ns.
        @test slices[1]["ts"] == 0.0
        @test slices[1]["dur"] == 500.0
        @test slices[1]["name"] == "GC (incremental)"
        @test slices[2]["ts"] == 1000.0
        @test slices[2]["dur"] == 1200.0
        @test slices[2]["name"] == "GC (full)"
        # The GC track gets a thread_name metadata event.
        names = [e for e in parsed["traceEvents"]
                 if get(e, "ph", "") == "M" && get(e, "name", "") == "thread_name"]
        @test any(e -> e["tid"] == 0 && e["args"]["name"] == "GC", names)
    end

    @testset "@perfetto captures GC events when the workload allocates" begin
        # Force several GCs inside the profiled block.
        disp = @perfetto begin
            for _ in 1:5
                xs = [rand(1000) for _ in 1:1000]
                GC.gc()
            end
        end
        @test disp isa ProfilePerfetto.PerfettoDisplay
        events = ProfilePerfetto._collect_gc_events()
        @test length(events) >= 1
        @test all(e -> e.end_ns >= e.start_ns, events)
    end
end
