#__runtime_jl

@inline _cron_is_valid(c::Cron) =
    !(isempty(c.minute) || isempty(c.hour) || isempty(c.day) ||
      isempty(c.month)  || isempty(c.weekday))

@inline _is_covering(::Type{P}, set::BitSet) where {P<:Period} =
    length(set) == (upper(P) - lower(P) + 1)

@inline function _day_matches(c::Cron, t::DateTime)
    in_dom = (day(t) ∈ c.day.set)
    in_dow = (dayofweek(t) ∈ c.weekday.set)

    dom_full = _is_covering(Day, c.day.set)
    dow_full = _is_covering(Week, c.weekday.set)

    if dom_full && dow_full
        return true
    elseif dom_full
        return in_dow
    elseif dow_full
        return in_dom
    else
        return (in_dom || in_dow)
    end
end

@inline function _next_ge_mask(mask::UInt64, v::Int, lo::Int, hi::Int)
    v < lo && (v = lo)
    v > hi && return nothing
    offs = v - lo
    shifted = mask >> offs
    if shifted != 0
        return lo + offs + trailing_zeros(shifted)
    end
    return nothing
end

@inline function _first_mask(mask::UInt64, lo::Int)
    return lo + trailing_zeros(mask)
end

@inline function _dom_mask_for(y::Int, m::Int, mask_dom::UInt64)::UInt64
    dim = Dates.daysinmonth(Date(y, m, 1))
    keep = (UInt64(1) << dim) - UInt64(1)
    return mask_dom & keep
end

function _next_matching_day_in_month_masked(c::Cron, y::Int, m::Int, start_day::Int)
    dom_full = _is_covering(Day,  c.day.set)
    dow_full = _is_covering(Week, c.weekday.set)
    dim = Dates.daysinmonth(Date(y, m, 1))
    start_day > dim && return nothing
    if dom_full && dow_full
        return start_day
    end
    dom_mask = _dom_mask_for(y, m, c.day.mask)
    function next_dom()
        dom_mask == 0 && return nothing
        return _next_ge_mask(dom_mask, start_day, 1, dim)
    end

    function next_dow()
        c.weekday.mask == 0 && return nothing
        start_date = Date(y, m, start_day)
        cw = dayofweek(start_date)
        best = typemax(Int)
        @inbounds for d in 0:6
            wd = ((cw - 1 + d) % 7) + 1
            if (c.weekday.mask & (UInt64(1) << (wd - 1))) != 0
                best = d
                break
            end
        end
        cand = start_day + best
        return (cand <= dim) ? cand : nothing
    end

    if dom_full
        return next_dow()
    elseif dow_full
        return next_dom()
    else
        d1 = next_dom()
        d2 = next_dow()
        return d1 === nothing ? d2 :
               d2 === nothing ? d1 :
               min(d1::Int, d2::Int)
    end
end

@inline function _prev_le_mask(mask::UInt64, v::Int, lo::Int, hi::Int)
    v > hi && (v = hi)
    v < lo && return nothing
    offs = v - lo
    truncated = offs >= 63 ? mask : (mask & ((UInt64(1) << (offs + 1)) - UInt64(1)))
    if truncated != 0
        return lo + (63 - leading_zeros(truncated))
    end
    return nothing
end

@inline function _last_mask(mask::UInt64, lo::Int)
    return lo + (63 - leading_zeros(mask))
end

function _prev_matching_day_in_month_masked(c::Cron, y::Int, m::Int, start_day::Int)
    dom_full = _is_covering(Day,  c.day.set)
    dow_full = _is_covering(Week, c.weekday.set)
    dim = Dates.daysinmonth(Date(y, m, 1))
    start_day < 1  && return nothing
    start_day > dim && (start_day = dim)
    if dom_full && dow_full
        return start_day
    end
    dom_mask = _dom_mask_for(y, m, c.day.mask)

    function prev_dom()
        dom_mask == 0 && return nothing
        return _prev_le_mask(dom_mask, start_day, 1, dim)
    end

    function prev_dow()
        c.weekday.mask == 0 && return nothing
        start_date = Date(y, m, start_day)
        cw = dayofweek(start_date)
        @inbounds for d in 0:6
            wd = ((cw - 1 - d) % 7) + 1
            if (c.weekday.mask & (UInt64(1) << (wd - 1))) != 0
                return start_day - d
            end
        end
        return nothing
    end

    if dom_full
        return prev_dow()
    elseif dow_full
        return prev_dom()
    else
        pd  = prev_dom()
        pdo = prev_dow()
        (pd === nothing)  && return pdo
        (pdo === nothing) && return pd
        return max(pd::Int, pdo::Int)
    end
end

@inline function _seek_prev_matching_dom!(c::Cron, y::Int, m::Int, mon_lo::Int, mon_hi::Int)
    yy = y
    mm = m
    while true
        dd = _prev_matching_day_in_month_masked(c, yy, mm, Dates.daysinmonth(Date(yy, mm, 1)))
        if dd !== nothing
            return (yy, mm, dd::Int)
        end
        pm = _prev_le_mask(c.month.mask, mm - 1, mon_lo, mon_hi)
        if pm === nothing
            yy -= 1
            mm  = _last_mask(c.month.mask, mon_lo)
        else
            mm = pm::Int
        end
    end
end

@inline function _seek_prev_month_then_dom!(c::Cron, y::Int, m::Int, mon_lo::Int, mon_hi::Int)
    yy = y
    pm = _prev_le_mask(c.month.mask, m - 1, mon_lo, mon_hi)
    mm = pm === nothing ? _last_mask(c.month.mask, mon_lo) : Int(pm)
    yy -= pm === nothing ? 1 : 0
    return _seek_prev_matching_dom!(c, yy, mm, mon_lo, mon_hi)
end


struct TonextIter
    c::Cron
    start::DateTime
    until::Union{Nothing,DateTime}
end

Base.eltype(::Type{TonextIter}) = DateTime
Base.IteratorSize(::Type{TonextIter}) = Base.SizeUnknown()

function Base.iterate(it::TonextIter)
    t = next_offset(it.c, it.start)
    it.until !== nothing && t > it.until && return nothing
    return (t, t)
end

function Base.iterate(it::TonextIter, state::DateTime)
    t = next_offset(it.c, state)
    it.until !== nothing && t > it.until && return nothing
    return (t, t)
end

"""
    next(c::Cron, dt::DateTime) -> DateTime

Return the next `DateTime` on a minute boundary that satisfies the cron schedule `c`,
starting from `dt` (inclusive).

!!! note
    The `day-of-month` and `day-of-week` fields are combined with **OR semantics**,
    unless one of them is `*`, in which case only the other is considered.

# Examples
```julia-repl
julia> using Dates

julia> next(Cron("*/5 * * * *"), DateTime("2025-01-01T12:03:00"))
2025-01-01T12:05:00

julia> next(Cron("0 14 * * *"), Date(2025,01,01))
2025-01-01T14:00:00
```
"""
function next(c::Cron, dt::DateTime)
    _cron_is_valid(c) || throw(CrontabError("Cron is not filled correctly or invalid"))
    t = ceil(dt, Minute)

    (min_lo, min_hi) = bounds(Minute)
    (hr_lo,  hr_hi)  = bounds(Hour)
    (mon_lo, mon_hi) = bounds(Month)
    while true # will run no more than number of rules (currently no more than 5)
        y = year(t); m = month(t); d = day(t); h = hour(t); mi = minute(t)

        if (c.month.mask & (UInt64(1) << (m - mon_lo))) == 0
            nm = _next_ge_mask(c.month.mask, m, mon_lo, mon_hi)
            if nm === nothing
                y += 1
                m  = _first_mask(c.month.mask, mon_lo)
            else
                m = nm::Int
            end
            d, h, mi = 1, 0, 0
            t = DateTime(y, m, d, h, mi)
            continue
        end

        if !_day_matches(c, t)
            nd = _next_matching_day_in_month_masked(c, y, m, d)
            if nd === nothing
                nm = _next_ge_mask(c.month.mask, m + 1, mon_lo, mon_hi)
                if nm === nothing
                    y += 1
                    m  = _first_mask(c.month.mask, mon_lo)
                else
                    m = nm
                end
                d, h, mi = 1, 0, 0
            else
                d = nd::Int; h = 0; mi = 0
            end
            t = DateTime(y, m, d, h, mi)
            continue
        end

        if (c.hour.mask & (UInt64(1) << (h - hr_lo))) == 0
            nh = _next_ge_mask(c.hour.mask, h, hr_lo, hr_hi)
            if nh === nothing
                nd = _next_matching_day_in_month_masked(c, y, m, d + 1)
                if nd === nothing
                    nm = _next_ge_mask(c.month.mask, m + 1, mon_lo, mon_hi)
                    if nm === nothing
                        y += 1
                        m  = _first_mask(c.month.mask, mon_lo)
                    else
                        m = nm
                    end
                    d = 1
                else
                    d = nd::Int
                end
                h, mi = _first_mask(c.hour.mask, hr_lo), 0
            else
                h, mi = nh, 0
            end
            t = DateTime(y, m, d, h, mi)
            continue
        end

        if (c.minute.mask & (UInt64(1) << (mi - min_lo))) == 0
            nmin = _next_ge_mask(c.minute.mask, mi, min_lo, min_hi)
            if nmin === nothing
                nh = _next_ge_mask(c.hour.mask, h + 1, hr_lo, hr_hi)
                if nh === nothing
                    nd = _next_matching_day_in_month_masked(c, y, m, d + 1)
                    if nd === nothing
                        nm = _next_ge_mask(c.month.mask, m + 1, mon_lo, mon_hi)
                        if nm === nothing
                            y += 1
                            m  = _first_mask(c.month.mask, mon_lo)
                        else
                            m = nm
                        end
                        d = 1
                    else
                        d = nd::Int
                    end
                    h = _first_mask(c.hour.mask, hr_lo)
                else
                    h = nh
                end
                mi = _first_mask(c.minute.mask, min_lo)
            else
                mi = nmin
            end
            t = DateTime(y, m, d, h, mi)
            continue
        end
        return t
    end
end

function next(c::Cron, start::TimeType)
    return next(c, DateTime(start))
end

"""
    prev(c::Cron, dt::DateTime) -> DateTime

Return the greatest `DateTime` on a minute boundary that satisfies the cron schedule `c`,
before `dt` (inclusive).

# Examples
```julia-repl
julia> using Dates

julia> prev(Cron("*/5 * * * *"), DateTime("2025-01-01T12:03:00"))
2025-01-01T12:00:00

julia> prev(Cron("0 * 23 * *"), Date(2025,01,01))
2024-12-23T23:00:00
```
"""
function prev(c::Cron, dt::DateTime)
    _cron_is_valid(c) || throw(CrontabError("Cron is not filled correctly or invalid"))
    t = floor(dt, Minute)
    (min_lo, min_hi) = bounds(Minute)
    (hr_lo,  hr_hi)  = bounds(Hour)
    (mon_lo, mon_hi) = bounds(Month)

    last_min = _last_mask(c.minute.mask, min_lo)::Int
    last_hr  = _last_mask(c.hour.mask,   hr_lo)::Int

    while true
        y = year(t); m = month(t); d = day(t); h = hour(t); mi = minute(t)

        if (c.month.mask & (UInt64(1) << (m - mon_lo))) == 0
            pm = _prev_le_mask(c.month.mask, m, mon_lo, mon_hi)
            if pm === nothing
                y -= 1
                m  = _last_mask(c.month.mask, mon_lo)
            else
                m = pm::Int
            end
            y, m, d = _seek_prev_matching_dom!(c, y, m, mon_lo, mon_hi)
            h  = _last_mask(c.hour.mask, hr_lo)::Int
            mi = _last_mask(c.minute.mask, min_lo)::Int
            t = DateTime(y, m, d, h, mi); continue
        end

        if !_day_matches(c, t)
            pd = _prev_matching_day_in_month_masked(c, y, m, d)
            if pd === nothing
                y, m, d = _seek_prev_month_then_dom!(c, y, m, mon_lo, mon_hi)
            else
                d = pd::Int
            end
            h = last_hr; mi = last_min
            t = DateTime(y, m, d, h, mi); continue
        end

        if (c.hour.mask & (UInt64(1) << (h - hr_lo))) == 0
            ph = _prev_le_mask(c.hour.mask, h, hr_lo, hr_hi)
            if ph === nothing
                pd = _prev_matching_day_in_month_masked(c, y, m, d - 1)
                if pd === nothing
                    y, m, d = _seek_prev_month_then_dom!(c, y, m, mon_lo, mon_hi)
                else
                    d = pd::Int
                end
                h = last_hr; mi = last_min
            else
                h = ph::Int; mi = last_min
            end
            t = DateTime(y, m, d, h, mi); continue
        end

        if (c.minute.mask & (UInt64(1) << (mi - min_lo))) == 0
            pmin = _prev_le_mask(c.minute.mask, mi, min_lo, min_hi)
            if pmin === nothing
                ph = _prev_le_mask(c.hour.mask, h - 1, hr_lo, hr_hi)
                if ph === nothing
                    pd = _prev_matching_day_in_month_masked(c, y, m, d - 1)
                    if pd === nothing
                        y, m, d = _seek_prev_month_then_dom!(c, y, m, mon_lo, mon_hi)
                    else
                        d = pd::Int
                    end
                    h = last_hr
                else
                    h = ph::Int
                end
                mi = last_min
            else
                mi = pmin::Int
            end
            t = DateTime(y, m, d, h, mi); continue
        end

        return t
    end
end

function prev(c::Cron, start::TimeType)
    return prev(c, DateTime(start))
end

function Base.wait(c::Cron; tz=UTC)
    now_dt = now(tz)
    fire_dt = next(c, now_dt)
    sleep(fire_dt - DateTime(now_dt))
end

"""
    timesteps(c::Cron, start::DateTime, n::Integer) -> Vector{DateTime}

Return `n` upcoming chrono-based times for cron schedule `c`, strictly after `start`.

# Examples
```julia-repl
julia> using Dates

julia> timesteps(Cron("*/15 * * * *"), DateTime("2025-01-01T12:03:00"), 4)
4-element Vector{DateTime}:
 2025-01-01T12:15:00
 2025-01-01T12:30:00
 2025-01-01T12:45:00
 2025-01-01T13:00:00

julia> timesteps(Cron("*/5 * * * *"), Date(2025,01,01), 2)
2-element Vector{DateTime}:
 2025-01-01T00:05:00
 2025-01-01T00:10:00
 
```
"""
function timesteps(c::Cron, start::DateTime, n::Integer)
    t = start + Minute(1)
    out = Vector{DateTime}(undef, n)
    @inbounds for i in 1:n
        t = next(c, t)
        out[i] = t
        t += Minute(1)
    end
    return out
end

function timesteps(c::Cron, start::TimeType, n::Integer)
    return timesteps(c, DateTime(start), n)
end
