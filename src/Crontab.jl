module Crontab

export Cron,
    CrontabError,
    next,
    prev,
    timesteps,
    pretty,
    prettyprint

using Dates
using PrecompileTools


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
        Cron("1/2,3-4", "1-3/4,5", "*", ".", "*")
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
