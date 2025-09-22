#__ prettyprint_jl

const WEEKDAY_NAMES = ("Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday")

weekday_name(v::Int) = (WEEKDAY_NAMES[v]) # fail, if v is not in (1..7)

label(::Type{Minute}) = "minute"
label(::Type{Hour})   = "hour"
label(::Type{Day})    = "day-of-month"
label(::Type{Month})  = "month"
label(::Type{Week})   = "day-of-week"

@inline function ordinal_suffix(n::Int)
    t = n % 10; h = n % 100
    (t == 1 && h != 11) ? "st" :
    (t == 2 && h != 12) ? "nd" :
    (t == 3 && h != 13) ? "rd" : "th"
end

ordinal(n::Int) = string(n, ordinal_suffix(n))

step(::Type{Minute}, s::Int) = s == 1 ? "every minute"       : "every $(ordinal(s)) minute"
step(::Type{Hour},   s::Int) = s == 1 ? "every hour"         : "every $(ordinal(s)) hour"
step(::Type{Day},    s::Int) = s == 1 ? "every day-of-month" : "every $(ordinal(s)) day-of-month"
step(::Type{Week},   s::Int) = s == 1 ? "every day-of-week"  : "every $(ordinal(s)) day-of-week"
step(::Type{Month},  s::Int) = s == 1 ? "every month"        : "every $s months"

range_suffix(::Type{P}, l::Int, r::Int) where {P<:Period} =
    (l == lower(P) && r == upper(P)) ? "" : " from $l through $r"

range_suffix(::Type{Week}, l::Int, r::Int) =
    (l == 1 && r == 7) ? "" : " from $(weekday_name(l)) through $(weekday_name(r))"

pretty(i::UnitInterval{Week}) = weekday_name(i.value)
pretty(i::UnitInterval{P}) where {P<:Period} =
    string(label(P), " ", i.value)

pretty(i::Interval{P}) where {P<:Period} =
    "every " * label(P) * range_suffix(P, i.start, i.stop)

pretty(i::PeriodInterval{P}) where {P<:Period} =
    step(P, i.step) * range_suffix(P, i.start, i.stop)

pretty(::CoveringInterval{P}) where {P<:Period} =
    "every " * label(P)


is_covering(t::TimeUnitIntervals{P}) where {P<:Period} =
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
    pretty(c::Cron) -> String

Returns a human-readable representation of a `Cron` schedule. Used internally when printing a `Cron`.

## Examples
```julia-repl
julia> pretty(Cron("*/15 * * * *"))
"At every 15th minute"

julia> pretty(Cron("0 14 * * 1-5"))
"At minute 0\\npast hour 14\\non every day-of-week from Monday through Friday"
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

prettyprint(c::Cron) = print(pretty(c))
prettyprint(io::IO, c::Cron) = print(io, pretty(c))
Base.show(io::IO, c::Cron) = prettyprint(io, c)
