#__ prettyprint_jl

const WEEKDAY_NAMES = ("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")

@inline weekday_name(v::Int) = (1 <= v <= 7 ? WEEKDAY_NAMES[v] : string(v))

@inline label(::Type{Minute}) = "minute"
@inline label(::Type{Hour})   = "hour"
@inline label(::Type{Day})    = "day-of-month"
@inline label(::Type{Month})  = "month"
@inline label(::Type{Week})   = "day-of-week"

@inline function ordinal_suffix(n::Int)
    t = n % 10; h = n % 100
    (t == 1 && h != 11) ? "st" :
    (t == 2 && h != 12) ? "nd" :
    (t == 3 && h != 13) ? "rd" : "th"
end
@inline ordinal(n::Int) = string(n, ordinal_suffix(n))

@inline step(::Type{Minute}, s::Int) = s == 1 ? "every minute"       : "every $(ordinal(s)) minute"
@inline step(::Type{Hour},   s::Int) = s == 1 ? "every hour"         : "every $(ordinal(s)) hour"
@inline step(::Type{Day},    s::Int) = s == 1 ? "every day-of-month" : "every $(ordinal(s)) day-of-month"
@inline step(::Type{Week},   s::Int) = s == 1 ? "every day-of-week"  : "every $(ordinal(s)) day-of-week"
@inline step(::Type{Month},  s::Int) = s == 1 ? "every month"        : "every $s months"

@inline range_suffix(::Type{P}, l::Int, r::Int) where {P<:Period} =
    (l == lower(P) && r == upper(P)) ? "" : " from $l through $r"

@inline range_suffix(::Type{Week}, l::Int, r::Int) =
    (l == 1 && r == 7) ? "" : " from $(weekday_name(l)) through $(weekday_name(r))"

@inline pretty(i::UnitInterval{Week}) = weekday_name(i.value)
@inline pretty(i::UnitInterval{P}) where {P<:Period} =
    string(label(P), " ", i.value)

@inline pretty(i::Interval{P}) where {P<:Period} =
    "every " * label(P) * range_suffix(P, i.start, i.stop)

@inline pretty(i::PeriodInterval{P}) where {P<:Period} =
    step(P, i.step) * range_suffix(P, i.start, i.stop)

@inline pretty(::CoveringInterval{P}) where {P<:Period} =
    "every " * label(P)

"""
    is_covering(t::TimeUnitIntervals{P}) where P<:Period -> Bool

Return `true` if `t` contains all possible values for period `P` (i.e. covers `*`).

# Examples
```julia-repl
julia> using Crontab

julia> t = Crontab.TimeUnitIntervals{Minute}(); Crontab.is_covering(t)
false
```
"""
@inline is_covering(t::TimeUnitIntervals{P}) where {P<:Period} =
    length(t.set) == (upper(P) - lower(P) + 1)

function pretty(t::TimeUnitIntervals{Minute})
    if isempty(t)
        return "no minute"
    end
    if all(x -> x isa UnitInterval{Minute}, t.intervals)
        vals = sort(collect(t.set))
        return "minute " * join(string.(vals), ", ")
    end
    return join(pretty.(t.intervals), " and ")
end

function pretty(t::TimeUnitIntervals{P}) where {P<:Period}
    if isempty(t)
        return "no " * label(P)
    end
    return join(pretty.(t.intervals), " and ")
end

"""
    pretty(c::Cron)::String

Return a human-readable description of the schedule.

# Examples
```julia-repl
julia> using Crontab

julia> println(pretty(Cron("*/15 * * * *")))
At every 15th minute

julia> println(pretty(Cron("0 14 * * 1-5")))
At minute 0
past hour 14
on every day-of-week from Monday through Friday
```
"""
function pretty(c::Cron)
    parts = String[]
    push!(parts, pretty(c.minute))
    for (field, prefix) in (
        (c.hour,    "past "),
        (c.day,     "on "),
        (c.month,   "in "),
        (c.weekday, "on "),
    )
        if !is_covering(field)
            push!(parts, prefix * pretty(field))
        end
    end
    return "At " * join(parts, '\n')
end

"""
    prettyprint(c::Cron)
    prettyprint(io::IO, c::Cron)

Print a human-readable description of the schedule.

# Examples
```julia-repl
julia> using Crontab

julia> prettyprint(Cron("*/15 * * * *"))
"At every 15th minute"
```
"""
prettyprint(c::Cron) = print(pretty(c))
prettyprint(io::IO, c::Cron) = print(io, pretty(c))
Base.show(io::IO, c::Cron) = prettyprint(io, c)
