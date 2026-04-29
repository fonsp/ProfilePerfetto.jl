### ---- Sample parsing

# One sample with per-thread metadata, as produced by Profile.fetch(; include_meta = true).
#
# Raw buffer layout per sample (see Julia stdlib Profile.jl — the `0, 0` pair is the
# block-end marker; a single `0` in the ips is a valid rogue null IP on some platforms):
#
#   ips..., thread_id, task_id, cpu_cycle_clock, sleepstate, 0, 0
#
# Offsets (from the trailing 0 at index `i`):
#   i-5 = thread_id,  i-4 = task_id,  i-3 = cpu_cycle_clock,  i-2 = sleepstate
struct Sample
    stack::Vector{UInt64}    # instruction pointers, leaf-first
    thread_id::UInt64
    task_id::UInt64
    timestamp_ticks::UInt64  # from cycleclock() — rdtsc on x86, cntvct_el0 on
                             # ARM. Not nanoseconds; needs calibration to ns.
    sleepstate::UInt64       # 1 = awake, 2 = sleeping, 3 = task-profiler fake
end

function _parse_samples(data::Vector{UInt64})
    samples = Sample[]
    n = length(data)
    sample_start = 1
    i = 6  # need i-5 to be a valid index
    while i <= n
        # A block-end is two consecutive zeros — but a rogue single zero IP can
        # appear, so also require a non-zero sleepstate just before it.
        if data[i] == 0 && data[i-1] == 0 && data[i-2] != 0
            thread_id = data[i-5]
            task_id = data[i-4]
            cpu_cycle = data[i-3]
            sleepstate = data[i-2]
            ips = data[sample_start:(i-6)]
            push!(samples, Sample(ips, thread_id, task_id, cpu_cycle, sleepstate))
            sample_start = i + 1
            i = sample_start + 5
        else
            i += 1
        end
    end
    return samples
end

# Pull the defining module out of a StackFrame's linfo, as a string. Returns
# "" when no module can be determined (C frames, top-level code without a
# MethodInstance, ip with no debug info).
function _frame_module(sf)::String
    li = sf.linfo
    li === nothing && return ""
    if li isa Core.MethodInstance
        d = li.def
        return d isa Module ? string(d) : string(d.module)
    elseif li isa Method
        return string(li.module)
    end
    return ""
end

# Flatten one sample's ips into a top-down list of (name, file, line, module)
# frames. When `filter_sentinel` is true, the result is truncated to only the
# frames strictly below `_SENTINEL_NAME`; samples that don't contain the
# sentinel at all return an empty vector.
function _stack_frames(
    stack::Vector{UInt64}, lidict; C::Bool = false, filter_sentinel::Bool = false
)
    result = Tuple{String,String,Int,String}[]
    # Raw stack is leaf-first; iterate in reverse for root-first (top-down).
    for ip in Iterators.reverse(stack)
        frames = get(lidict, ip, nothing)
        if frames === nothing
            push!(result, ("ip_0x$(string(ip; base = 16))", "", 0, ""))
            continue
        end
        # Each ip may correspond to multiple (inlined) StackFrames,
        # stored innermost-first. Reverse for top-down order.
        for sf in Iterators.reverse(frames)
            if !C && sf.from_c
                continue
            end
            push!(result, (string(sf.func), string(sf.file), sf.line, _frame_module(sf)))
        end
    end
    if filter_sentinel
        idx = findfirst(f -> f[1] == _SENTINEL_NAME, result)
        idx === nothing && return Tuple{String,String,Int,String}[]
        return result[(idx+1):end]
    end
    return result
end
