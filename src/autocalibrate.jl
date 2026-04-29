### ---- Auto-calibrating profile runs
#
# The `@autoperfetto` macro runs the user expression multiple times, sharpening
# the sampling delay on each round. Only the final run is displayed. Each next
# delay is the tightest value that satisfies three constraints simultaneously:
#
#   (1) Buffer fill: don't exceed ~50 % of the sample buffer.
#         Δ ≥ Δ_prev · used / (N · target_fill)
#
#   (2) Overhead: don't inflate wall-clock runtime by more than `max_inflation`.
#       Model: T_measured = T_raw / (1 − c/Δ), where c is per-sample overhead.
#       Solving for Δ with R = max_inflation:
#         Δ ≥ c · R / (R − 1)
#       c is estimated from each completed round:
#         c = Δ · (T − T_raw) / T       (clamped to ≥ 0)
#       Round 1 at 10 ms is treated as T_raw (overhead ≈ 0.01 % at that rate).
#
#   (3) Max step per round: `delay_next ≥ delay_prev / max_step`. Prevents
#       overshooting the overhead sweet spot in one jump, since the first few
#       rounds haven't observed enough overhead yet to estimate `c` reliably.
#
# The loop stops when the target equals the current delay (converged), we're
# already at `min_delay`, or we've hit `max_rounds`.

const _AUTO_INITIAL_DELAY  = 0.01        # 10 ms
const _AUTO_MIN_DELAY      = 1e-7        # 0.1 μs floor
const _AUTO_BUFFER_SLOTS   = 10_000_000  # ~80 MB; cheap, hard to overflow
const _AUTO_TARGET_FILL    = 0.5         # aim to fill ~half the buffer
const _AUTO_MAX_ROUNDS     = 6
const _AUTO_CONVERGE_TOL   = 0.2         # stop when |target-delay|/delay < tol
const _AUTO_MAX_INFLATION  = 10.0        # max T_measured / T_raw
const _AUTO_MAX_STEP       = 8.0         # max shrink factor per round

_fmt_delay(d) = d >= 1e-3 ? string(round(d * 1e3; digits = 2), " ms") :
                            string(round(d * 1e6; digits = 1), " μs")
_fmt_time(t)  = t >= 1    ? string(round(t;        digits = 2), " s")  :
                            string(round(t * 1e3;  digits = 1), " ms")

function _autocalibrate(
    thunk;
    initial_delay::Float64 = _AUTO_INITIAL_DELAY,
    min_delay::Float64     = _AUTO_MIN_DELAY,
    buffer_slots::Int      = _AUTO_BUFFER_SLOTS,
    max_rounds::Int        = _AUTO_MAX_ROUNDS,
    max_inflation::Float64 = _AUTO_MAX_INFLATION,
    max_step::Float64      = _AUTO_MAX_STEP,
)
    delay = initial_delay
    local wall_ns::UInt64 = zero(UInt64)
    T_raw = NaN  # set from round 1

    for round_i in 1:max_rounds
        Profile.clear()
        Profile.init(n = buffer_slots, delay = delay)

        t0 = time_ns()
        Profile.@profile 🐔🚀🧦(thunk)
        wall_ns = time_ns() - t0

        used = Int(Profile.len_data())
        T    = wall_ns / 1e9
        frac = used / buffer_slots

        # Round 1 is coarse enough that per-sample overhead is negligible, so
        # we treat its wall-clock time as the overhead-free baseline. Later
        # rounds refine downward if they happen to be faster (JIT warmup).
        if round_i == 1
            T_raw = T
        else
            T_raw = min(T_raw, T)
        end
        inflation = T / T_raw

        # (2) Estimate per-sample cost c from observed inflation, then derive
        # the overhead-respecting delay floor. Ignore if inflation is within
        # noise — the resulting c would be spurious.
        c = (T > 1.05 * T_raw) ? delay * (T - T_raw) / T : 0.0
        delay_oh = c > 0 ? c * max_inflation / (max_inflation - 1) : 0.0

        # (1) Buffer-fill floor.
        delay_buf = used == 0 ? 0.0 :
                    delay * used / (buffer_slots * _AUTO_TARGET_FILL)

        # (3) Max step per round — dampens aggressive jumps when c isn't yet
        # known, which is exactly what made the very first sharpening step
        # overshoot in practice.
        delay_step = delay / max_step

        target = max(min_delay, delay_buf, delay_oh, delay_step)

        at_floor  = delay <= min_delay * (1 + _AUTO_CONVERGE_TOL)
        converged = abs(target - delay) / delay < _AUTO_CONVERGE_TOL
        last_one  = round_i == max_rounds
        # Workload too short to sample meaningfully: any further sharpening
        # just adds profiler overhead without collecting samples.
        too_fast  = round_i > 1 && used == 0 && delay < T_raw

        if frac > 0.95
            @warn "autoperfetto: buffer filled at Δ=$(_fmt_delay(delay)); trace truncated. Consider raising `min_delay`."
        end
        if inflation > max_inflation * 1.5
            @warn "autoperfetto: sampling overhead inflated runtime $(round(inflation; digits = 1))× at Δ=$(_fmt_delay(delay))."
        end

        if at_floor || converged || last_one || too_fast
            @info "autoperfetto: $(_fmt_time(T)) at Δ=$(_fmt_delay(delay)) " *
                  "($(round(Int, 100frac))% buffer, $(round(inflation; digits = 1))× baseline, round $round_i)"
            break
        end

        @info "autoperfetto: calibrating — $(_fmt_time(T)) at Δ=$(_fmt_delay(delay)) ($(round(inflation; digits = 1))×), sharpening to Δ=$(_fmt_delay(target))"
        delay = target
    end

    data, lidict = Profile.retrieve(; include_meta = true)
    return data, lidict, wall_ns
end

function _autoperfetto_macro(f, expr)
    quote
        local _data, _lidict, _wall_ns =
            $(_autocalibrate)(() -> $(esc(expr)))
        $(f)(_data, _lidict; filter_sentinel = true, wall_time_ns = _wall_ns)
    end
end

"""
    @autoperfetto expr

Like [`@perfetto`](@ref), but automatically tunes the profile sampling rate.

The expression is run several times: first at a coarse 10 ms sampling delay
to measure how long it takes, then again at a sharper delay chosen so the
profile buffer lands around half-full. Only the final, sharpest run is shown.

This gives useful flame charts for both millisecond-scale and second-scale
workloads without the caller having to pick a `delay` by hand.

The expression is executed **multiple times**. Don't use it on code with
observable side effects; use [`@perfetto`](@ref) instead.

# Example
```julia
using ProfilePerfetto

@autoperfetto my_expensive_function(args...)
```
"""
macro autoperfetto(expr)
    _autoperfetto_macro(:perfetto_view, expr)
end

const var"@autoperfetto_view" = var"@autoperfetto"

"""
    @autoperfetto_open expr

Like [`@autoperfetto`](@ref), but opens the resulting flame chart in a web
browser instead of returning an inline display.

The expression is executed **multiple times**; see [`@autoperfetto`](@ref).
"""
macro autoperfetto_open(expr)
    _autoperfetto_macro(:perfetto_open, expr)
end
