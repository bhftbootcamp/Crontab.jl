using Test
using Dates
using Crontab
using Aqua

# Parsing - valid
@testset "Parsing (valid)" begin
    @test Cron("* * * * *") isa Cron
    @test Cron("*/5 * * * *") isa Cron
    @test Cron("1-10/2 * * * *") isa Cron
    @test Cron("1,5,10 * * * *") isa Cron
    @test Cron("0 0 * 3 *") isa Cron                 # every midnight in March
    @test Cron("* * 1-31 1,3,12 1-7") isa Cron
    @test Cron("0 14 * * 1-5") isa Cron             # 14:00 on weekdays
    @test Cron("6-30/6 9-17 * * 1-5") isa Cron      # every 6 min, work hours, weekdays
    @test Cron(". * * * *") isa Cron                # empty minutes (parse OK, run invalid)
    @test Cron("  *   *   *   *   *  ") isa Cron    # extra whitespace is OK
    # Base.parse
    @test Base.parse(Crontab.Cron, "*/5 1-2 10-11 2,4 1-5") isa Cron
end

# Parsing - invalid
@testset "Parsing (invalid)" begin
    @test_throws CrontabError Cron("61 * * * *")      # minute out of range
    @test_throws CrontabError Cron("*/0 * * * *")     # zero step
    @test_throws CrontabError Cron("* * * *")         # only 4 fields
    @test_throws CrontabError Cron("* * * * * *")     # 6 fields
    @test_throws CrontabError Cron("a * * * *")       # non-int token
    @test_throws CrontabError Cron("1-3-5 * * * *")   # malformed range
    @test_throws CrontabError Cron("10-/2 * * * *")   # malformed stepped base
    @test_throws CrontabError Cron("*/ * * * *")      # missing step number
    @test_throws CrontabError Cron("5-1 * * * *")     # reversed interval
    @test_throws CrontabError Cron("-1 * * * *")      # negative
    @test_throws CrontabError Cron("* -1 * * *")      # negative
    @test_throws CrontabError Cron("* * 0 * *")       # out of range day-of-month
    @test_throws CrontabError Cron("* * * 0 *")       # out of range month
    @test_throws CrontabError Cron("* * * * 0")       # out of range day-of-week
    @test_throws CrontabError Cron("1,,3 * * * *")    # empty token between commas
end

# Intervals core types
@testset "Intervals core" begin
    using Crontab: intervals, UnitInterval, Interval, PeriodInterval, CoveringInterval,
                   TimeUnitIntervals

    # constructors/bounds
    @test UnitInterval{Minute}(0) isa UnitInterval{Minute}
    @test_throws CrontabError UnitInterval{Minute}(60)

    @test Interval{Hour}(0, 23) isa Interval{Hour}
    @test_throws CrontabError Interval{Hour}(10, 9)

    @test_throws CrontabError PeriodInterval{Day}(1, 31, 0)

    # iteration ranges
    @test collect(intervals(UnitInterval{Minute}(5))) == 5:5
    @test collect(intervals(Interval{Minute}(2, 4))) == 2:4
    @test collect(intervals(PeriodInterval{Minute}(0, 5, 2))) == 0:2:5
    @test collect(intervals(CoveringInterval{Week}())) == 1:7

    # TimeUnitIntervals union and printing
    t = TimeUnitIntervals{Minute}()
    @test isempty(t)
    Crontab.union!(t, UnitInterval{Minute}(10))
    @test !isempty(t) && 10 in t.set

    @test string(Interval{Minute}(1, 3)) == "1-3"
    @test string(UnitInterval{Minute}(7)) == "7"
    @test string(PeriodInterval{Minute}(1, 9, 2)) == "1-9/2"
    @test string(CoveringInterval{Minute}()) == "*"
end

# next(): basic minute stepping
@testset "next() - basic minutes" begin
    cron = Cron("*/5 * * * *")
    @test next(cron, DateTime("2025-01-01T12:03:00"))  == DateTime("2025-01-01T12:05:00")
    @test next(cron, DateTime("2025-01-01T12:05:00"))  == DateTime("2025-01-01T12:05:00")  # on boundary
    @test next(cron, DateTime("2025-01-01T12:59:00")) == DateTime("2025-01-01T13:00:00") # hour rollover

    cron2 = Cron("6-30/5 * * * *")  # 6,11,16,21,26
    @test next(cron2, DateTime("2025-03-03T00:03:00"))  == DateTime("2025-03-03T00:06:00")
    @test next(cron2, DateTime("2025-03-03T00:06:00"))  == DateTime("2025-03-03T00:06:00")
    @test next(cron2, DateTime("2025-03-03T00:27:00")) == DateTime("2025-03-03T01:06:00")  # spill to next hour set
end

# next(): hour/day/month filters
@testset "next() - hour/day/month filters" begin
    # Only at 14:00 any day
    c_14 = Cron("0 14 * * *")
    @test next(c_14, DateTime("2025-01-01T13:59:00")) == DateTime("2025-01-01T14:00:00")
    @test next(c_14, DateTime("2025-01-01T14:00:00"))  == DateTime("2025-01-01T14:00:00")
    @test next(c_14, DateTime("2025-01-01T14:01:00"))  == DateTime("2025-01-02T14:00:00")

    # Every day in March at 00:00
    c_march = Cron("0 0 * 3 *")
    @test next(c_march, DateTime("2024-03-31T10:10:00")) == DateTime("2025-03-01T00:00:00")
    @test next(c_march, DateTime("2025-03-01T00:00:00"))    == DateTime("2025-03-01T00:00:00")
end

# DOM vs DOW (OR semantics) + covering rules
@testset "next() - day-of-month vs day-of-week" begin
    # 13th or Tuesday, at midnight
    c = Cron("0 0 13 * 2")
    @test next(c, DateTime("2025-03-10T10:00:00")) == DateTime("2025-03-11T00:00:00") # Mon -> Tue
    @test next(c, DateTime("2025-03-11T00:00:00"))  == DateTime("2025-03-11T00:00:00") # already Tue
    @test next(c, DateTime("2025-03-12T10:00:00")) == DateTime("2025-03-13T00:00:00") # Wed -> 13th

    # Only Tuesdays (DOM is covering)
    c2 = Cron("0 0 * * 2")
    @test next(c2, DateTime("2025-03-09T10:00:00")) == DateTime("2025-03-11T00:00:00")

    # Only 1st/15th (DOW is covering)
    c3 = Cron("0 0 1,15 * *")
    @test next(c3, DateTime("2025-03-01T00:00:00"))  == DateTime("2025-03-01T00:00:00")
    @test next(c3, DateTime("2025-03-02T00:00:00"))  == DateTime("2025-03-15T00:00:00")
end

# next(): multi-field combos
@testset "next() - multi-field combos" begin
    # Every 10th minute during 9–17h on weekdays
    c = Cron("*/10 9-17 * * 1-5")
    @test next(c, DateTime("2025-03-07T09:03:00"))   == DateTime("2025-03-07T09:10:00")  # Fri morning
    @test next(c, DateTime("2025-03-07T17:59:00")) == DateTime("2025-03-10T09:00:00")  # Fri -> next Mon 09:00

    # Specific days in specific months
    c2 = Cron("30 6 1,15 4,10 *") # 06:30 on 1st/15th of Apr/Oct
    @test next(c2, DateTime("2025-04-01T00:00:00"))  == DateTime("2025-04-01T06:30:00")
    @test next(c2, DateTime("2025-04-01T06:30:00")) == DateTime("2025-04-01T06:30:00")
    @test next(c2, DateTime("2025-04-01T06:31:00")) == DateTime("2025-04-15T06:30:00")
    @test next(c2, DateTime("2025-04-16T07:00:00")) == DateTime("2025-10-01T06:30:00")
end

# timesteps()
@testset "timesteps()" begin
    cron = Cron("*/15 * * * *")
    ts = timesteps(cron, DateTime("2025-01-01T12:03:00"), 5)
    @test ts == [
        DateTime("2025-01-01T12:15:00"),
        DateTime("2025-01-01T12:30:00"),
        DateTime("2025-01-01T12:45:00"),
        DateTime("2025-01-01T13:00:00"),
        DateTime("2025-01-01T13:15:00"),
    ]
    @test issorted(ts)

    # start exactly on boundary -> next tick
    c2 = Cron("*/5 * * * *")
    @test timesteps(c2, DateTime("2025-01-01T12:10:00"), 1) == [DateTime("2025-01-01T12:15:00")]

    # n = 0 -> empty
    @test timesteps(c2, DateTime("2025-01-01T12:10:00"), 0) == DateTime[]
end

# Boundaries & leap years
@testset "Boundaries & leap years" begin
    # 31st days at specific minutes in select months (long months)
    cron = Cron("*/30 23 31 1,3,5,7,8,10,12 *")
    @test next(cron, DateTime("2025-01-31T23:40:00")) == DateTime("2025-03-31T23:00:00")  # Feb has no 31st

    # Leap year 29 Feb
    c_leap = Cron("0 0 29 2 *")
    @test next(c_leap, DateTime("2023-02-28T01:00:00")) == DateTime("2024-02-29T00:00:00")
    @test next(c_leap, DateTime("2024-02-29T00:00:00")) == DateTime("2024-02-29T00:00:00")
    @test next(c_leap, DateTime("2024-03-01T00:00:00"))  == DateTime("2028-02-29T00:00:00")  # next leap year
end

# Invalid schedule usage (empty unions) - next() should throw
@testset "Invalid schedule usage" begin
    c = Cron(". * * * *")  # invalid to run (minutes empty)
    @test_throws CrontabError next(c, now())
end

# Pretty & show
@testset "Pretty & show" begin
    # Smoke tests: show must not throw
    show(IOBuffer(), Cron("*/10 4 3,*/20 3-10/3 3-5/2"))
    show(IOBuffer(), Cron("* * * * *"))
    show(IOBuffer(), Cron(". 10-20 . . ."))
    @test true

    # String/pretty expectations (from README-like examples)
    @test string(Cron("*/4 * * * *")) == "*/4 * * * *"
    @test string(Cron("* */3 * * *")) == "* */3 * * *"
    @test string(Cron("* * 1-7 * *")) == "* * 1-7 * *"
    @test string(Cron("* * */10 * *")) == "* * */10 * *"
    @test string(Cron("* * * */2 *")) == "* * * */2 *"
    @test string(Cron("* * * 2-4/2 *")) == "* * * 2-4/2 *"
    @test string(Cron("* * * * 1")) == "* * * * 1"
    @test string(Cron("* * * * 1-5")) == "* * * * 1-5"
    @test string(Cron("* * * * 6,7")) == "* * * * 6,7"
    @test string(Cron("0 0 1 * *")) == "0 0 1 * *"
    @test string(Cron("*/15 14 * * *")) == "*/15 14 * * *"
    @test string(Cron("0 9-18 * * 1-5")) == "0 9-18 * * 1-5"
    @test string(Cron("30 23 28-31 1,3,5,7,8,10,12 *")) == "30 23 28-31 1,3,5,7,8,10,12 *"
    
    @test pretty(Cron("* * * * *")) == "At every minute"
    @test pretty(Cron("0 * * * *")) == "At minute 0"
    @test pretty(Cron("1-5 * * * *")) == "At every minute from 1 through 5"
    @test pretty(Cron("*/4 * * * *")) == "At every 4th minute"
    @test pretty(Cron("* */3 * * *")) == "At every minute\npast every 3rd hour"
    @test pretty(Cron("* * 1-7 * *")) == "At every minute\non every day-of-month from 1 through 7"
    @test pretty(Cron("* * */10 * *")) == "At every minute\non every 10th day-of-month"
    @test pretty(Cron("* * * */2 *")) == "At every minute\nin every 2 months"
    @test pretty(Cron("* * * 2-4/2 *")) == "At every minute\nin every 2 months from 2 through 4"
    @test pretty(Cron("* * * * 1")) == "At every minute\non Monday"
    @test pretty(Cron("* * * * 1-5")) == "At every minute\non every day-of-week from Monday through Friday"
    @test pretty(Cron("* * * * 6,7")) == "At every minute\non Saturday and Sunday"
    @test pretty(Cron("0 0 1 * *")) == "At minute 0\npast hour 0\non day-of-month 1"
    @test pretty(Cron("*/15 14 * * *")) == "At every 15th minute\npast hour 14"
    @test pretty(Cron("0 9-18 * * 1-5")) == "At minute 0\npast every hour from 9 through 18\non every day-of-week from Monday through Friday"
    @test pretty(Cron("30 23 28-31 1,3,5,7,8,10,12 *")) == "At minute 30\npast hour 23\non every day-of-month from 28 through 31\nin month 1 and month 3 and month 5 and month 7 and month 8 and month 10 and month 12"
end

@testset "Keyword/Tuple constructors" begin
    # Keyword API with wildcards and fields
    c_kw = Cron(; minute="*/5", hour="9-18", weekday="1-5")
    @test next(c_kw, DateTime("2025-03-07T09:03:00")) == DateTime("2025-03-07T09:05:00")

    # Tuple-style with wildcards as "*"
    c_tp = Cron("0", "14,18", "*", "*", "1-5")
    @test next(c_tp, DateTime("2025-01-01T17:50:00")) == DateTime("2025-01-01T18:00:00")
end


@testset "prev() - basic minutes" begin
    c = Cron("*/5 * * * *")
    @test prev(c, DateTime("2025-01-01T12:03:00")) == DateTime("2025-01-01T12:00:00")
    @test prev(c, DateTime("2025-01-01T12:05:00")) == DateTime("2025-01-01T12:05:00")  # boundary
end

@testset "prev() - hour/day/month filters" begin
    # Only at 14:00 any day
    c_14 = Cron("0 14 * * *")
    @test prev(c_14, DateTime("2025-01-02T15:00:00")) == DateTime("2025-01-02T14:00:00")
    @test prev(c_14, DateTime("2025-01-01T13:00:00")) == DateTime("2024-12-31T14:00:00")

    # Every day in March at 00:00
    c_march = Cron("0 0 * 3 *")
    @test prev(c_march, DateTime("2025-04-01T00:00:00")) == DateTime("2025-03-31T00:00:00")
end

@testset "prev() - day-of-month vs day-of-week (OR semantics)" begin
    # 13th OR Tuesday, at midnight
    c = Cron("0 0 13 * 2")
    @test prev(c, DateTime("2025-03-12T00:00:00")) == DateTime("2025-03-11T00:00:00")  # Wed -> Tue
    @test prev(c, DateTime("2025-03-14T00:00:00")) == DateTime("2025-03-13T00:00:00")  # Fri -> 13th
    @test prev(c, DateTime("2025-03-13T00:00:00")) == DateTime("2025-03-13T00:00:00")  # boundary
end

@testset "prev() - boundaries & leap years" begin
    # Long-month 31st rule; stepping back over February
    cron = Cron("*/30 23 31 1,3,5,7,8,10,12 *")
    @test prev(cron, DateTime("2025-03-01T00:00:00")) == DateTime("2025-01-31T23:30:00")

    # Leap day
    c_leap = Cron("0 0 29 2 *")
    @test prev(c_leap, DateTime("2024-03-01T00:00:00")) == DateTime("2024-02-29T00:00:00")
    @test prev(c_leap, DateTime("2023-03-01T00:00:00")) == DateTime("2020-02-29T00:00:00")
end

@testset "prev() - invalid schedule usage" begin
    c = Cron(". * * * *")  # empty minutes: parse OK, runtime invalid
    @test_throws CrontabError prev(c, now())
end

