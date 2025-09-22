#__runtime_jl

@inline _cron_is_valid(c::Cron) =
    !(isempty(c.minute) || isempty(c.hour) || isempty(c.day) ||
      isempty(c.month)  || isempty(c.weekday))

@inline _is_covering(::Type{P}, set::BitSet) where {P<:Period} =
    length(set) == (upper(P) - lower(P) + 1)

@inline function _next_in_set(set::BitSet, v::Int, ::Type{P}) where {P<:Period}
    x = v
    hi = upper(P)
    while x <= hi
        if x in set
            return x
        end
        x += 1
    end
    return nothing
end

@inline function _day_matches(c::Cron, t::DateTime)
    in_dom = (day(t)       ∈ c.day.set)
    in_dow = (dayofweek(t) ∈ c.weekday.set)

    dom_full = _is_covering(Day,  c.day.set)
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

"""
    next(c::Cron, dt::DateTime) -> DateTime

Return the next `DateTime` on a minute boundary that satisfies the cron schedule `c`,
starting from `dt` (inclusive).

!!! note
    The `day-of-month` and `day-of-week` fields are combined with **OR semantics**,
    unless one of them is `*`, in which case only the other is considered.

# Examples
```julia-repl
using Crontab, Dates

c = Cron("*/5 * * * *");

julia> next(c, DateTime("2025-01-01T12:03:00"))
2025-01-01T12:05:00

julia> next(Cron("0 14 * * *"), DateTime("2025-01-01T14:00:00"))
2025-01-01T14:00:00
```
"""
function next(c::Cron, dt::DateTime)
    _cron_is_valid(c) || throw(CrontabError("Cron is not filled correctly or invalid"))
    t = ceil(dt, Minute)
    while true
        if !(month(t) ∈ c.month.set)
            nm = _next_in_set(c.month.set, month(t), Month)
            if nm === nothing
                t = DateTime(year(t) + 1, 1, 1, 0, 0)
            else
                t = DateTime(year(t), nm, 1, 0, 0)
            end
            continue
        end
        if !_day_matches(c, t)
            t = DateTime(Date(t) + Day(1), Time(0))
            continue
        end
        if !(hour(t) ∈ c.hour.set)
            nh = _next_in_set(c.hour.set, hour(t), Hour)
            if nh === nothing
                t = DateTime(Date(t) + Day(1), Time(0))
            else
                t = DateTime(Date(t), Time(nh, 0))
            end
            continue
        end
        if !(minute(t) ∈ c.minute.set)
            nmin = _next_in_set(c.minute.set, minute(t), Minute)
            if nmin === nothing
                nh = _next_in_set(c.hour.set, hour(t) + 1, Hour)
                if nh === nothing
                    t = DateTime(Date(t) + Day(1), Time(0))
                else
                    t = DateTime(Date(t), Time(nh, 0))
                end
            else
                t = DateTime(Date(t), Time(hour(t), nmin))
            end
            continue
        end
        return t
    end
end

"""
    next(c::Cron, start) -> DateTime

Like `next(c, ::DateTime)`, but accepts any `start` that can be converted to
`DateTime` (e.g. `ZonedDateTime` from TimeZones).
"""
function next(c::Cron, start::TimeType)
    return next(c, DateTime(start))
end

"""
    Base.wait(c::Cron, tz=UTC)::Nothing

Block until the next time that matches `c`, using `now(tz)` as the current time.
`tz` can be anything supported by `now(tz)` (e.g. `UTC` from Dates or `tz"Region/City"` from TimeZones).

# Examples
```julia-repl
julia> using Crontab, Dates

julia> cron = Cron("*/2 * * * *")  # every 2 minutes

julia> @async begin
           println("Waiting for cron at ", now(UTC))
           wait(cron; tz=UTC)
           println("Triggered at ", now(UTC))
       end
Waiting for cron at DateTime("2025-06-11T14:59:30")
Triggered at DateTime("2025-06-11T15:00:00")
```
"""
function Base.wait(c::Cron; tz=UTC)
    now_dt = now(tz)
    fire_dt = next(c, now_dt)
    sleep(fire_dt - DateTime(now_dt))
end

"""
    timesteps(c::Cron, start::DateTime, n::Integer)::Vector{DateTime}

Return `n` upcoming times for `c`, strictly after `start`.
Each time is on a minute boundary.

# Arguments
- `c`: Cron schedule.
- `start`: Starting timestamp (exclusive).
- `n`: Number of results.

# Returns
A `Vector{DateTime}` in ascending order.

# Examples
```julia-repl
using Crontab, Dates

c = Cron("*/15 * * * *");

julia> timesteps(c, DateTime("2025-01-01T12:03:00"), 4)
4-element Vector{DateTime}:
 2025-01-01T12:15:00
 2025-01-01T12:30:00
 2025-01-01T12:45:00
 2025-01-01T13:00:00
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

"""
    timesteps(c::Cron, start, n::Integer) -> Vector{DateTime}

Like `timesteps(c, ::DateTime, n)`, but accepts any `start` that can be converted
to `DateTime` (e.g. `ZonedDateTime` from TimeZones).
"""
function timesteps(c::Cron, start::TimeType, n::Integer)
    return timesteps(c, DateTime(start), n)
end
