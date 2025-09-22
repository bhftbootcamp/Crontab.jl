#__ cront_jl

bounds(::Type{Minute}) = (0, 59)
bounds(::Type{Hour})   = (0, 23)
bounds(::Type{Day})    = (1, 31)
bounds(::Type{Month})  = (1, 12)
bounds(::Type{Week})   = (1, 7)

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

@inline _bitindex(::Type{P}, v::Int) where {P<:Period} = v - lower(P)
@inline _bit(::Type{P}, v::Int) where {P<:Period} = UInt64(1) << _bitindex(P, v)

@inline function _mask_for(::Type{P}, r::AbstractUnitRange{Int})::UInt64 where {P<:Period}
    m = UInt64(0)
    @inbounds for v in r
        m |= _bit(P, v)
    end
    return m
end
@inline function _mask_for(::Type{P}, r::StepRange{Int,Int})::UInt64 where {P<:Period}
    m = UInt64(0)
    @inbounds for v in r
        m |= _bit(P, v)
    end
    return m
end

mutable struct TimeUnitIntervals{P<:Period}
    set::BitSet
    intervals::Vector{AbstractInterval{P}}
    mask::UInt64
    TimeUnitIntervals{P}() where {P} = new(BitSet(), AbstractInterval{P}[], UInt64(0))
    TimeUnitIntervals{P}(set::BitSet, ivs::Vector{<:AbstractInterval{P}}) where {P} =
        new(set, AbstractInterval{P}[ivs...], begin
            m = UInt64(0)
            @inbounds for v in set
                m |= _bit(P, Int(v))
            end
            m
        end)
end

Base.isempty(t::TimeUnitIntervals) = isempty(t.set)

function Base.union!(a::TimeUnitIntervals{P}, i::AbstractInterval{P}) where {P}
    r = intervals(i)
    union!(a.set, BitSet(r))
    a.mask |= _mask_for(P, r)
    push!(a.intervals, i)
    return a
end

function Base.union!(a::TimeUnitIntervals{P}, b::TimeUnitIntervals{P}) where {P}
    union!(a.set, b.set)
    a.mask |= b.mask
    append!(a.intervals, b.intervals)
    return a
end

"""
    Cron

Internal representation of a cron schedule. Construct a cron schedule from a five-field expression: `minute` `hour` `day` `month` `weekday`.
Supports `*`, `/`, `-`, `,`, and `.` where `.` denotes an empty set.
# Examples
```julia-repl
julia> Cron("*/15 * * * *")
"At every 15th minute"

julia> Cron("*", "*", "*", "*", "1")
"At every minute\non Monday"

julia> Cron(minute="0", hour="0", day="1")
"At minute 0\npast hour 0\non day-of-month 1"
```
"""
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

Base.parse(::Type{Cron}, expr::AbstractString) = Cron(expr)
