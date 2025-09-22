"""
    Crontab

Lightweight cron-style scheduling for Julia.

Provides parsing of five-field cron expressions, computation of next run times,
blocking waits, and pretty printing.

# Examples
```julia-repl
using Crontab, Dates

julia> c = Cron("*/15 * * * *")
At every 15th minute

julia> next(c, DateTime("2025-01-01T12:03:00"))
2025-01-01T12:15:00
```
"""
module Crontab

export Cron,
    CrontabError,
    next,
    timesteps,
    pretty,
    prettyprint

using Dates
using PrecompileTools

"""
    CrontabError

Error type for all parsing/validation failures during cron construction and use.

Thrown for out-of-range values, malformed tokens, or when the cron string does
not have exactly five fields.

# Examples
```julia-repl
julia> using Crontab

julia> Cron("61 * * * *")
ERROR: CrontabError: Dates.Minute value out of range [0..59], got 61
```
"""
struct CrontabError <: Exception
    message::String
end
Base.showerror(io::IO, e::CrontabError) = print(io, "CrontabError: ", e.message)

include("cron.jl")
include("parser.jl")
include("prettyprint.jl")
include("runtime.jl")

@setup_workload begin
    @compile_workload begin
        Cron("*/4 1-3 2 1-3/4 2,3")
        pretty(Cron("3/7,3 * 10-11 2,4 1-5"))
        pretty(Cron("1-3/4,3 *,3-4 10-11 2,4 1-5"))
        pretty(Cron(". . . . ."))
        string(Cron("* * * * *"))
        pretty(Cron("1 1 1 1 1"))
        pretty(Cron("1-2 1-2 1-2 1-2 1-2"))
        pretty(Cron("1-2/4 1-2/4 1-2/4 1-2/4 1-2/4"))
        pretty(Cron("1-2/4,* 1-2/4,* 1-2/4,* 1-2/4,* 1-2/4,*"))
        pretty(Cron("*/4,3 */4,3 */4,3 */4,3 */4,3"))
        pretty(Cron("3/4,3 3/4,3 3/4,3 3/4,3 3/4,3"))
    end
end

end
