### ---- Allocation profile → Perfetto events
#
# `Profile.Allocs.fetch()` returns samples of the form (type, stacktrace, size)
# with NO per-sample timestamp and NO thread info. To show them alongside CPU
# samples in Perfetto we synthesize a dedicated track (separate pid) where each
# span's duration equals the allocation size. The track's total time span is
# scaled to the CPU wall time, so the flame-graph tab — which aggregates by
# duration — naturally reads as "total bytes per function".
#
# Samples are sorted by their top-down stack so visually-similar allocations
# cluster together into fat bars rather than a confetti of singletons. Without
# real timestamps this is the only way to produce a readable timeline view.

function _alloc_stack_frames(
    stacktrace, filter_sentinel::Bool, type_obj
)
    result = Tuple{String,String,Int}[]
    # Profile.Allocs stacktrace is leaf-first; iterate reverse for root-first.
    for sf in Iterators.reverse(stacktrace)
        sf.from_c && continue
        push!(result, (string(sf.func), string(sf.file), sf.line))
    end
    if filter_sentinel
        idx = findfirst(f -> f[1] == _SENTINEL_NAME, result)
        idx === nothing && return Tuple{String,String,Int}[]
        result = result[(idx+1):end]
    end
    # Append the allocated type as a synthetic leaf frame. With pure stack
    # frames the flame graph collapses all allocations inside a given function
    # into one bar — prepending the type lets users see which allocations
    # dominate by *type* as well as by call site.
    if type_obj !== nothing
        push!(result, (string(type_obj), "<type>", 0))
    end
    return result
end

function _allocs_to_events!(
    events::Vector{Any},
    alloc_results,
    cpu_wall_us::Union{Nothing,Float64};
    filter_sentinel::Bool = false,
    pid::Int = 2,
    tid::Int = 1,
)
    alloc_results === nothing && return nothing
    allocs = alloc_results.allocs
    isempty(allocs) && return nothing

    stacks = Vector{Vector{Tuple{String,String,Int}}}(undef, length(allocs))
    sizes = Vector{Int}(undef, length(allocs))
    for (i, a) in enumerate(allocs)
        stacks[i] = _alloc_stack_frames(a.stacktrace, filter_sentinel, a.type)
        sizes[i] = Int(a.size)
    end

    total_size = sum(sizes)
    total_size == 0 && return nothing

    # Fit alloc spans into the CPU wall-time window so the two tracks share a
    # meaningful time axis. No CPU data → fall back to "1 byte = 1 µs" which
    # at least gives a visible track whose widths are proportional to size.
    range_us = cpu_wall_us === nothing ? Float64(total_size) : cpu_wall_us
    us_per_byte = range_us / Float64(total_size)

    order = sortperm(stacks; by = s -> map(f -> f[1], s))

    prev = Tuple{String,String,Int}[]
    t::Float64 = 0.0
    for i in order
        stack = stacks[i]
        dur = Float64(sizes[i]) * us_per_byte
        if isempty(stack)
            t += dur
            continue
        end
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
                    "pid" => pid,
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
                    "pid" => pid,
                    "tid" => tid,
                    "ts" => t,
                    "name" => name,
                    "args" => Dict("file" => file, "line" => line),
                ),
            )
        end
        prev = stack
        t += dur
    end
    for j in length(prev):-1:1
        push!(
            events,
            Dict(
                "ph" => "E",
                "pid" => pid,
                "tid" => tid,
                "ts" => t,
                "name" => prev[j][1],
            ),
        )
    end

    push!(
        events,
        Dict(
            "ph" => "M",
            "name" => "process_name",
            "pid" => pid,
            "tid" => tid,
            "args" => Dict("name" => "Allocations"),
        ),
    )
    push!(
        events,
        Dict(
            "ph" => "M",
            "name" => "thread_name",
            "pid" => pid,
            "tid" => tid,
            "args" => Dict("name" => "Allocations ($(Base.format_bytes(total_size)))"),
        ),
    )
    return nothing
end
