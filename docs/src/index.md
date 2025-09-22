# Crontab.jl

⏰ **Crontab** - Lightweight cron parsing & scheduling for Julia. Crontab.jl provides a small, fast cron expression parser and runtime helpers to compute next/previous execution times, generate upcoming timestamps, and block until the next trigger.

## Installation

If you haven't installed our [local registry](https://github.com/bhftbootcamp/Green) yet, do that first:
```
] registry add https://github.com/bhftbootcamp/Green.git
```

Then, to install Crontab, simply use the Julia package manager:
```
] add Crontab
```

## Usage

Compute next match (inclusive of the minute boundary)
```julia
c = Cron("*/5 * * * *")
next_time = next(c, DateTime("2025-01-01T12:03:00")) # 2025-01-01T12:05:00
```

Previous match (inclusive of the minute boundary)
```julia
c = Cron("*/5 * * * *")
prev_time = prev(c, DateTime("2025-01-01T12:03:00")) # 2025-01-01T12:00:00
```

Compute next match offset-style (not chrono-style)
```julia
c = Cron("*/5 * * * *")
next_offset_time = next_offset(c, DateTime("2025-01-01T12:03:00")) # 2025-01-01T12:08:00
```

Generate 4 upcoming triggers strictly after a start time
```julia
c = Cron("*/5 * * * *")
ts = timesteps(c, DateTime("2025-01-01T12:03:00"), 4) # 12:05, 12:10, 12:15, 12:20
```

Create infinite offset-based iterator from starting point
```julia
c = Cron("*/5 * * * *")
start = DateTime("2025-01-01T12:07:00")
xs = collect(take(gen_times(c, start), 4))
# [
#         DateTime("2025-01-01T12:12:00"),
#         DateTime("2025-01-01T12:17:00"),
#         DateTime("2025-01-01T12:22:00"),
#         DateTime("2025-01-01T12:27:00"),
# ]
```

Block until the next trigger (uses system clock)
```julia
c = Cron("*/5 * * * *")
@async begin
    println("Waiting…", now(UTC))
    wait(c; tz=UTC)
    println("Triggered at", now(UTC))
end
```

Get next leap year from date
```julia
c_leap = Cron("0 0 29 2 *")
next(c_leap, DateTime("2024-03-01T00:00:00")) # DateTime("2028-02-29T00:00:00")
```

Business hours on weekdays (every 10 minutes)
```julia
cron = Cron(; minute="*/10", hour="9-17", weekday="1-5")  # 09:00–17:59, Mon–Fri

while true
    wait(cron)
    @async begin
        # do useful work
    end
end
```

Twice a month: 1st and 15th at 06:30 (Apr/Oct)
```julia
cron = Cron("30 6 1,15 4,10 *")  # Apr/Oct 1st and 15th at 06:30
```

Get the next time from an arbitrary point
```julia
using Crontab, Dates

c = Cron("*/5 * * * *")

next(c, DateTime("2025-01-01T12:03:00"))  # => 2025-01-01T12:05:00
```

Example of running tasks asynchronously on cron schedules
```julia
using Dates
using Crontab
using CryptoExchangeAPIs.Binance

function spawn_job(name::AbstractString, cron::Cron, times::Int, job::Function; run_now::Bool=true)
    return @async begin
        if run_now
            job()
        end
        for _ in 1:times
            wait(cron; tz=UTC)
            job()
        end
        println("$name done")
        flush(stdout)
    end
end

function heartbeat_job()
    println("heartbeat at $(now(UTC))")
    flush(stdout)
end

function report_job()
    res = Binance.Spot.Ticker.ticker(; symbol = "ADAUSDT")
    println("ADA/USDT price: ", res.result.lastPrice, " at $(now(UTC))")
    flush(stdout)
end

# Start two concurrent cron-driven tasks
t1 = spawn_job("heartbeat", Cron("*/1 * * * *"), 3, heartbeat_job)
t2 = spawn_job("report",    Cron("*/2 * * * *"), 2, report_job)

# Wait for both to finish
fetch(t1)
fetch(t2)
```
