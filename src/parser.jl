#__ parser_jl

@inline function _parseint(what::AbstractString, x::AbstractString)::Int
    v = tryparse(Int, strip(x))
    v === nothing && throw(CrontabError("invalid $what: cannot parse '$x' as Int"))
    return v
end

@inline function _parsefield(::Type{P}, expr::AbstractString) where {P<:Period}
    s = strip(expr)
    s == "." && return TimeUnitIntervals{P}()
    s == "*" && return TimeUnitIntervals{P}(BitSet(lower(P):upper(P)),
                                    AbstractInterval{P}[CoveringInterval{P}()])
    acc = TimeUnitIntervals{P}()
    pname = string(nameof(P))
    idxstart(x) = x isa UnitRange ? first(x) : x
    idxstop(x)  = x isa UnitRange ? last(x)  : x
    for (i, raw) in enumerate(split(s, ','; keepempty=true))
        tok = strip(raw)
        isempty(tok) && throw(CrontabError("empty token at position $i in $(pname) field"))
        tok == "." && continue
        slash = findfirst('/', tok)
        @views if slash !== nothing
            sidx = idxstart(slash)
            base = strip(tok[firstindex(tok):sidx-1])
            step_str = strip(tok[nextind(tok, sidx):lastindex(tok)])
            isempty(base) && throw(CrontabError("invalid $(pname) token '$tok': missing base before '/'"))
            isempty(step_str) && throw(CrontabError("invalid $(pname) token '$tok': missing step after '/'"))
            step = _parseint("$(pname) step", step_str)
            step >= 1 || throw(CrontabError("invalid $(pname) step: must be ≥ 1, got $step"))
            local l::Int, r::Int
            if base == "*"
                l, r = lower(P), upper(P)
            else
                dash = findfirst('-', base)
                if dash !== nothing
                    didx = idxstart(dash)
                    a = strip(base[firstindex(base):didx-1])
                    b = strip(base[nextind(base, didx):lastindex(base)])
                    l = _parseint("$(pname) start", a)
                    r = _parseint("$(pname) stop",  b)
                else
                    v = _parseint("$(pname) value", base)
                    l, r = v, upper(P)
                end
            end
            union!(acc, PeriodInterval{P}(l, r, step))
            continue
        end
        if tok == "*"
            union!(acc, CoveringInterval{P}())
            continue
        end
        dash = findfirst('-', tok)
        @views if dash !== nothing
            didx = idxstart(dash)
            a = strip(tok[firstindex(tok):didx-1])
            b = strip(tok[nextind(tok, didx):lastindex(tok)])
            l = _parseint("$(pname) start", a)
            r = _parseint("$(pname) stop",  b)
            union!(acc, Interval{P}(l, r))
        else
            v = _parseint("$(pname) value", tok)
            union!(acc, UnitInterval{P}(v))
        end
    end
    return acc
end


