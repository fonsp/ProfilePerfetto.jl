### ---- Capture Julia GC events during a profile run
#
# Julia exposes C-level pre/post GC callbacks via `jl_gc_set_cb_pre_gc` and
# `jl_gc_set_cb_post_gc` (from `julia_gcext.h`). They fire under JL_NOTSAFEPOINT:
# no Julia allocations, no locks, no task yields. Julia GC is stop-the-world, so
# at most one collection is in flight at a time — we stash the current start
# in a single slot and commit (start, end, full, thread_id) in the post callback.

struct GCEvent
    start_ns::UInt64
    end_ns::UInt64
    full::Bool
    thread_id::Int
end

const _GC_MAX_EVENTS = 100_000

const _gc_start_ns = Vector{UInt64}(undef, _GC_MAX_EVENTS)
const _gc_end_ns = Vector{UInt64}(undef, _GC_MAX_EVENTS)
const _gc_full = Vector{Cint}(undef, _GC_MAX_EVENTS)
const _gc_tid = Vector{Cint}(undef, _GC_MAX_EVENTS)
const _gc_count = Ref{Int}(0)
const _gc_pending_start = Ref{UInt64}(0)
const _gc_pending_full = Ref{Cint}(0)
const _gc_pending_tid = Ref{Cint}(0)

# Trampolines live in `Ref`s populated in `__init__` — `@cfunction` must be
# executed at runtime (not cached in the precompile image).
const _gc_pre_cb_ptr = Ref{Ptr{Cvoid}}(C_NULL)
const _gc_post_cb_ptr = Ref{Ptr{Cvoid}}(C_NULL)

function _gc_pre_cb(full::Cint)::Cvoid
    _gc_pending_start[] = ccall(:jl_hrtime, UInt64, ())
    _gc_pending_full[] = full
    _gc_pending_tid[] = Cint(ccall(:jl_threadid, Int16, ()))
    return nothing
end

function _gc_post_cb(full::Cint)::Cvoid
    end_ns = ccall(:jl_hrtime, UInt64, ())
    idx = _gc_count[] + 1
    if idx <= _GC_MAX_EVENTS
        @inbounds _gc_start_ns[idx] = _gc_pending_start[]
        @inbounds _gc_end_ns[idx] = end_ns
        @inbounds _gc_full[idx] = _gc_pending_full[]
        @inbounds _gc_tid[idx] = _gc_pending_tid[]
        _gc_count[] = idx
    end
    return nothing
end

function _gc_init_callbacks()
    _gc_pre_cb_ptr[] = @cfunction(_gc_pre_cb, Cvoid, (Cint,))
    _gc_post_cb_ptr[] = @cfunction(_gc_post_cb, Cvoid, (Cint,))
    return nothing
end

function _gc_start_logging()
    _gc_count[] = 0
    ccall(:jl_gc_set_cb_pre_gc, Cvoid, (Ptr{Cvoid}, Cint), _gc_pre_cb_ptr[], 1)
    ccall(:jl_gc_set_cb_post_gc, Cvoid, (Ptr{Cvoid}, Cint), _gc_post_cb_ptr[], 1)
    return nothing
end

function _gc_stop_logging()
    ccall(:jl_gc_set_cb_pre_gc, Cvoid, (Ptr{Cvoid}, Cint), _gc_pre_cb_ptr[], 0)
    ccall(:jl_gc_set_cb_post_gc, Cvoid, (Ptr{Cvoid}, Cint), _gc_post_cb_ptr[], 0)
    return nothing
end

function _collect_gc_events()
    n = _gc_count[]
    events = Vector{GCEvent}(undef, n)
    @inbounds for i in 1:n
        events[i] = GCEvent(
            _gc_start_ns[i],
            _gc_end_ns[i],
            _gc_full[i] != 0,
            Int(_gc_tid[i]),
        )
    end
    return events
end
