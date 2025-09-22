#__ parser_jl

@inline function _parseint(what::AbstractString, x::AbstractString)::Int
    v = tryparse(Int, strip(x))
    v === nothing && throw(CrontabError("invalid $what: cannot parse '$x' as Int"))
    return v
end

function _parsefield(::Type{P}, expr::AbstractString) where {P<:Period}
    s = strip(expr)
    if s == "."
        return TimeUnitIntervals{P}()
    elseif s == "*"
        return TimeUnitIntervals{P}(BitSet(lower(P):upper(P)),
                                    AbstractInterval{P}[CoveringInterval{P}()])
    elseif occursin(',', s)
        acc = TimeUnitIntervals{P}()
        for (i, raw) in enumerate(split(s, ','; keepempty=true))
            tok = strip(raw)
            isempty(tok) && throw(CrontabError("empty token at position $i in $(nameof(P)) field"))
            union!(acc, _parsefield(P, tok))
        end
        return acc
    elseif occursin('/', s)
        base, step_str = split(s, "/"; limit=2)
        isempty(base)     && throw(CrontabError("invalid $(nameof(P)) token '$s': missing base before '/'"))
        isempty(step_str) && throw(CrontabError("invalid $(nameof(P)) token '$s': missing step after '/'"))
        step = _parseint("$(nameof(P)) step", step_str)
        step >= 1 || throw(CrontabError("invalid $(nameof(P)) step: must be ≥ 1, got $step"))

        local l::Int, r::Int
        if base == "*"
            l, r = lower(P), upper(P)
        elseif occursin('-', base)
            a, b = split(base, "-"; limit=2)
            l = _parseint("$(nameof(P)) start", a)
            r = _parseint("$(nameof(P)) stop",  b)
        else
            v = _parseint("$(nameof(P)) value", base)
            l, r = v, upper(P)
        end
        ensure_inbounds(P, l, "start"); ensure_inbounds(P, r, "stop")
        l <= r || throw(CrontabError("invalid $(nameof(P)) interval: start ($l) must be ≤ stop ($r)"))
        return TimeUnitIntervals{P}(BitSet(l:step:r),
                                    AbstractInterval{P}[PeriodInterval{P}(l, r, step)])
    elseif occursin('-', s)
        a, b = split(s, "-"; limit=2)
        l = _parseint("$(nameof(P)) start", a)
        r = _parseint("$(nameof(P)) stop",  b)
        ensure_inbounds(P, l, "start"); ensure_inbounds(P, r, "stop")
        l <= r || throw(CrontabError("invalid $(nameof(P)) interval: start ($l) must be ≤ stop ($r)"))
        return TimeUnitIntervals{P}(BitSet(l:r), AbstractInterval{P}[Interval{P}(l, r)])
    else
        v = _parseint("$(nameof(P)) value", s)
        ensure_inbounds(P, v, "value")
        return TimeUnitIntervals{P}(BitSet([v]), AbstractInterval{P}[UnitInterval{P}(v)])
    end
end


