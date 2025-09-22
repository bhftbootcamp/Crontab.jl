# Crontab.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://bhftbootcamp.github.io/Crontab.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://bhftbootcamp.github.io/Crontab.jl/dev/)
[![Build Status](https://github.com/bhftbootcamp/Crontab.jl/actions/workflows/Coverage.yml/badge.svg?branch=master)](https://github.com/bhftbootcamp/Crontab.jl/actions/workflows/Coverage.yml?query=branch%3Amaster)
[![Coverage](https://codecov.io/gh/bhftbootcamp/Crontab.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/bhftbootcamp/Crontab.jl)
[![Registry](https://img.shields.io/badge/registry-Green-green)](https://github.com/bhftbootcamp/Green)

⏰ **Crontab** — lightweight cron-style scheduling for Julia. Write schedules with the familiar `* * * * *` syntax, compute the next run times, and drive your jobs easily.

## Installation

```julia
] add Crontab
```

## Quick start

### Every 2 minutes
```julia
using Crontab, Dates

cron = Cron("*/2 * * * *")  # every 2 minutes

while true
    wait(cron)                      # blocks until next tick
    println("Tick at ", now(UTC))   # do your work here
end
# prints e.g.: Tick at DateTime("2025-01-01T12:00:00")
```

### Next N run times
```julia
using Crontab, Dates

cron = Cron("*/15", "*", "*", "*", "*")

julia> timesteps(cron, DateTime("2025-01-01T12:03:00"), 5)
5-element Vector{DateTime}:
 2025-01-01T12:15:00
 2025-01-01T12:30:00
 2025-01-01T12:45:00
 2025-01-01T13:00:00
 2025-01-01T13:15:00
```

```julia
julia> pretty(Cron("*/15 14 * * *"))
At every 15th minute
past hour 14
```

## Real‑world recipes

### Business hours on weekdays (every 10 minutes)
```julia
using Crontab, Dates

cron = Cron(; minute="*/10", hour="9-17", weekday="1-5")  # 09:00–17:59, Mon–Fri
while true
    wait(cron)
    @async begin
        # do useful work
    end
end
```

### Twice a month: 1st and 15th at 06:30 (Apr/Oct)
```julia
cron = Cron("30 6 1,15 4,10 *")  # Apr/Oct 1st and 15th at 06:30
```

### Run an external Julia script daily at 09:00 UTC
```julia
using Crontab

cron = Cron("0", "9", "*", "*", "*")  # every day at 09:00

while true
    wait(cron)
    run(`$(Base.julia_cmd()) /absolute/path/to/trade_summary.jl --symbol=AAPL`)
end
```

### Get the next time from an arbitrary point
```julia
using Crontab, Dates
c = Cron("*/5 * * * *")
next(c, DateTime("2025-01-01T12:03:00"))  # => 2025-01-01T12:05:00
```

## Cron syntax

Five fields separated by spaces:

1. `minute` (0–59)
2. `hour` (0–23)
3. `day-of-month` (1–31)
4. `month` (1–12)
5. `day-of-week` (1–7, 1=Monday)

Supported tokens:

- `*` — all values
- `a-b` — inclusive range
- `*/k` or `a-b/k` — step
- `a,b,c` — list
- `.` — empty (parses, but schedule cannot be executed)

`day-of-month` is combined with `day-of-week` using OR semantics (unless one of them is `*`).

## API overview

- `Cron(str)` — parse a string into a schedule
- `next(cron, dt)` — the next run time (inclusive)
- `timesteps(cron, start, n)` — the next `n` run times after `start`
- `wait(cron)` — block until the next run time
- `pretty(cron)` — human-readable description; `show(cron)` prints it
