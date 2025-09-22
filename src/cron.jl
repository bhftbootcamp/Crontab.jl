#__ cront_jl

"""
    bounds(::Type{Minute | Hour | Day | Month | Week}) -> (Int, Int)

Return the inclusive lower and upper bounds for a given time unit.

# Examples
```julia-repl
julia> using Crontab

julia> Crontab.bounds(Minute)
(0, 59)

julia> Crontab.bounds(Day)
(1, 31)
```
"""
bounds(::Type{Minute}) = (0, 59)
bounds(::Type{Hour})   = (0, 23)
bounds(::Type{Day})    = (1, 31)
bounds(::Type{Month})  = (1, 12)
bounds(::Type{Week})   = (1, 7)

"""
    lower(::Type{P}) where P<:Period -> Int
    upper(::Type{P}) where P<:Period -> Int

Return the lower/upper inclusive bounds for the period `P`.

# Examples
```julia-repl
julia> using Crontab

julia> Crontab.lower(Month), Crontab.upper(Month)
(1, 12)
```
"""
lower(::Type{P}) where {P<:Period} = first(bounds(P))
upper(::Type{P}) where {P<:Period} = last(bounds(P))

@inline function ensure_inbounds(::Type{P}, v::Int, what::AbstractString) where {P<:Period}
    (lower(P) <= v <= upper(P)) || throw(CrontabError("$P $what out of range [$(lower(P))..$(upper(P))], got $v"))
    return v
end

abstract type AbstractInterval{P<:Period} end

struct UnitInterval{P<:Period} <: AbstractInterval{P}
    value::Int
    function UnitInterval{P}(v::Integer) where {P<:Period}
        vv = ensure_inbounds(P, Int(v), "value")
        new{P}(vv)
    end
end

struct Interval{P<:Period} <: AbstractInterval{P}
    start::Int
    stop::Int
    function Interval{P}(start::Integer, stop::Integer) where {P<:Period}
        s = Int(start); e = Int(stop)
        s <= e || throw(CrontabError("invalid $P interval: start ($s) must be ≤ stop ($e)"))
        ensure_inbounds(P, s, "start"); ensure_inbounds(P, e, "stop")
        new{P}(s, e)
    end
end

struct PeriodInterval{P<:Period} <: AbstractInterval{P}
    start::Int
    stop::Int
    step::Int
    function PeriodInterval{P}(start::Integer, stop::Integer, step::Integer) where {P<:Period}
        s = Int(start); e = Int(stop); k = Int(step)
        s <= e || throw(CrontabError("invalid $P interval: start ($s) must be ≤ stop ($e)"))
        k >= 1 || throw(CrontabError("invalid $P step: must be ≥ 1, got $k"))
        ensure_inbounds(P, s, "start"); ensure_inbounds(P, e, "stop")
        new{P}(s, e, k)
    end
end

struct CoveringInterval{P<:Period} <: AbstractInterval{P} end

intervals(i::UnitInterval)       = i.value:i.value
intervals(i::Interval)           = i.start:i.stop
intervals(i::PeriodInterval)     = i.start:i.step:i.stop
intervals(::CoveringInterval{P}) where {P<:Period} = lower(P):upper(P)

struct TimeUnitIntervals{P<:Period}
    set::BitSet
    intervals::Vector{AbstractInterval{P}}
    TimeUnitIntervals{P}() where {P} = new(BitSet(), AbstractInterval{P}[])
    TimeUnitIntervals{P}(set::BitSet, ivs::Vector{<:AbstractInterval{P}}) where {P} =
        new(set, AbstractInterval{P}[ivs...])
end

Base.isempty(t::TimeUnitIntervals) = isempty(t.set)

function Base.union!(a::TimeUnitIntervals{P}, i::AbstractInterval{P}) where {P}
    union!(a.set, BitSet(intervals(i)))
    push!(a.intervals, i)
    return a
end
function Base.union!(a::TimeUnitIntervals{P}, b::TimeUnitIntervals{P}) where {P}
    union!(a.set, b.set)
    append!(a.intervals, b.intervals)
    return a
end

struct Cron
    minute::TimeUnitIntervals{Minute}
    hour::TimeUnitIntervals{Hour}
    day::TimeUnitIntervals{Day}
    month::TimeUnitIntervals{Month}
    weekday::TimeUnitIntervals{Week}
end

Base.string(i::Interval)        = string(i.start, "-", i.stop)
Base.string(i::UnitInterval)    = string(i.value)
Base.string(::CoveringInterval) = "*"
Base.string(t::TimeUnitIntervals) = isempty(t) ? "." : join(string.(t.intervals), ",")
function Base.string(i::PeriodInterval{P}) where {P<:Period}
    return if i.start == lower(P) && i.stop == upper(P)
        string("*/", i.step)
    else
        string(i.start, "-", i.stop, "/", i.step)
    end
end
function Base.string(c::Cron)
    return join(string.((c.minute, c.hour, c.day, c.month, c.weekday)), " ")
end

@inline _fieldstr(x::AbstractString) = strip(x)
@inline _fieldstr(::Colon) = "*"

"""
    Cron(::AbstractString)

Construct a cron schedule from a five-field expression: minute hour day month weekday.
Supports `*`, `/`, `-`, `,`, and `.` where `.` denotes an empty set. The `timezone`
is stored on the schedule and used by blocking operations.

Notes: If any field is empty (i.e. `.`), the schedule is unfilled and `next` will throw.

# Examples
```julia-repl
julia> using Crontab

julia> Cron("*/15 * * * *")
At every 15th minute

julia> Cron("0 14 * * 1-5")
At minute 0
past hour 14
on every day-of-week from Monday through Friday
```
"""

function Cron(s::AbstractString)
    parts = split(strip(s); keepempty=false)
    length(parts) == 5 || throw(CrontabError("invalid cron string (expect 5 fields)"))
    return Cron(parts[1], parts[2], parts[3], parts[4], parts[5])
end
function Cron(minute::AbstractString,
              hour::AbstractString,
              day::AbstractString,
              month::AbstractString,
              weekday::AbstractString)
    return Cron(
        _parsefield(Minute, minute),
        _parsefield(Hour, hour),
        _parsefield(Day, day),
        _parsefield(Month, month),
        _parsefield(Week, weekday),
    )
end
function Cron(; minute::AbstractString="*",
               hour::AbstractString="*",
               day::AbstractString="*",
               month::AbstractString="*",
               weekday::AbstractString="*")
    return Cron(minute, hour, day, month, weekday)
end

"""
    Base.parse(::Type{Cron}, ::AbstractString)

Parse a cron expression into a `Cron` schedule. Equivalent to calling `Cron(str)`.

# Examples
```julia-repl
julia> using Crontab

julia> Base.parse(Crontab.Cron, "0 14 * * 1-5")
At minute 0
past hour 14
on every day-of-week from Monday through Friday
```
"""
Base.parse(::Type{Cron}, expr::AbstractString) = Cron(expr)
