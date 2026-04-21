### ---- Perfetto JSON generation

# Walk through samples per thread in timestamp order and emit Begin/End events
# such that adjacent samples sharing a common stack prefix merge into a span.
function _samples_to_perfetto_json(
    data::Vector{UInt64},
    lidict;
    sample_interval_us::Float64 = 1000.0,
    filter_sentinel::Bool = false,
    wall_time_ns::Union{Nothing,UInt64} = nothing,
)
    samples = _parse_samples(data)
    events = Any[]
    isempty(samples) && return JSON.json(
        Dict(
            "traceEvents" => events,
            "metadata" => Dict(
                "clock-domain" => "MONO",
                "command_line" => "Julia Profile",
            ),
        ),
    )

    # Group by thread and sort by tick timestamp so each thread has a contiguous
    # sample stream, independent of interleaving in the raw buffer.
    by_thread = Dict{UInt64,Vector{Sample}}()
    for s in samples
        push!(get!(by_thread, s.thread_id, Sample[]), s)
    end
    for v in values(by_thread)
        sort!(v; by = s -> s.timestamp_ticks)
    end

    # Calibrate ticks → ns. Profile metadata timestamps come from `cycleclock()`,
    # which is rdtsc on x86 (~GHz) and cntvct_el0 on ARM (~24 MHz on Apple
    # Silicon) — neither is nanoseconds. If we know the wall-clock duration the
    # profile ran for, derive ns-per-tick from the sample tick span. Otherwise
    # assume ticks ≈ ns, which is wrong on every real platform but at least
    # produces a trace that loads.
    t0_ticks = minimum(s.timestamp_ticks for s in samples)
    t1_ticks = maximum(s.timestamp_ticks for s in samples)
    ns_per_tick::Float64 = 1.0
    if wall_time_ns !== nothing && t1_ticks > t0_ticks
        ns_per_tick = Float64(wall_time_ns) / Float64(t1_ticks - t0_ticks)
    end

    for (tid, thread_samples) in by_thread
        stacks = [
            _stack_frames(s.stack, lidict; filter_sentinel) for s in thread_samples
        ]
        ts_us = [
            Float64(Int64(s.timestamp_ticks) - Int64(t0_ticks)) * ns_per_tick / 1000
            for s in thread_samples
        ]

        prev = Tuple{String,String,Int}[]
        last_t::Float64 = 0.0
        for (stack, t) in zip(stacks, ts_us)
            last_t = t
            # When `filter_sentinel` drops everything, the sampler either caught
            # the sentinel itself executing or a stack unrelated to the workload.
            # Treat these as "nothing interesting to show" — keep prev open so
            # the span doesn't needlessly fragment.
            isempty(stack) && continue
            # Merge on (name, file) only — the `line` of a non-leaf frame is
            # the current call-site inside that function, which drifts as the
            # function hits different sub-expressions and would otherwise
            # needlessly split one span into many.
            k = 0
            while k < length(stack) &&
                      k < length(prev) &&
                      stack[k+1][1] == prev[k+1][1] &&
                      stack[k+1][2] == prev[k+1][2]
                k += 1
            end
            for j in length(prev):-1:(k+1)
                push!(
                    events,
                    Dict(
                        "ph" => "E",
                        "pid" => 1,
                        "tid" => tid,
                        "ts" => t,
                        "name" => prev[j][1],
                    ),
                )
            end
            for j in (k+1):length(stack)
                name, file, line = stack[j]
                push!(
                    events,
                    Dict(
                        "ph" => "B",
                        "pid" => 1,
                        "tid" => tid,
                        "ts" => t,
                        "name" => name,
                        "args" => Dict("file" => file, "line" => line),
                    ),
                )
            end
            prev = stack
            last_t = t
        end
        # Close anything still open — extend by one sample interval so the
        # final span is visible rather than zero-width.
        final_t = last_t + sample_interval_us
        for j in length(prev):-1:1
            push!(
                events,
                Dict(
                    "ph" => "E",
                    "pid" => 1,
                    "tid" => tid,
                    "ts" => final_t,
                    "name" => prev[j][1],
                ),
            )
        end
    end

    return JSON.json(
        Dict(
            "traceEvents" => events,
            "metadata" => Dict(
                "clock-domain" => "MONO",
                "command_line" => "Julia Profile",
            ),
        ),
    )
end

function _profile_delay_us()::Float64
    try
        Float64(ccall(:jl_profile_delay_nsec, UInt64, ())) / 1000
    catch
        1000.0
    end
end

function _default_name()
    return "$(Dates.Time(Dates.now())) Julia profile"
end
