 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

extension Int64 {
     
    @inlinable
    static var leapoch: Int64 {
        .secondsFromEpochToYear2000 + .secondsPerDay * (31 + 29)
    }

    @inlinable
    static var secondsFromEpochToYear2000: Int64 {
        946_684_800
    }

    @inlinable
    static var daysPer400Years: Int64 {
        365 * 400 + 97
    }

    @inlinable
    static var daysPer100Years: Int64 {
        365 * 100 + 24
    }

    @inlinable
    static var daysPer4Years: Int64 {
        365 * 4 + 1
    }

    @inlinable
    static var secondsPerDay: Int64 {
        24 * 60 * 60
    }

    @inlinable
    static var secondsPerYear: Int64 {
        .secondsPerDay * .daysPerYear
    }

    @inlinable
    static var daysPerYear: Int64 {
        365
    }

    @inlinable
    static func daysInMonth(_ month: Int) -> Int64 {
         
         
        switch month {
        case 0, 2, 4, 5, 7, 9, 10:
            return 31
        case 1, 3, 6, 8:
            return 30
        case 11:
            return 29
        default:
            fatalError()
        }
    }

    @inlinable
    var utcDateFromTimestamp: (year: Int, month: Int, day: Int, hours: Int, minutes: Int, seconds: Int) {
        let secs = self - .leapoch
        var (days, remsecs) = secs.quotientAndRemainder(dividingBy: 86400)

         
        if remsecs < 0 {
             
             
            remsecs &+= .secondsPerDay
            days &-= 1
        }

        var (qcCycles, remdays) = days.quotientAndRemainder(dividingBy: .daysPer400Years)
        if remdays < 0 {
             
            remdays &+= .daysPer400Years
            qcCycles &-= 1
        }

         
         
        var cCycles = remdays / .daysPer100Years
        if cCycles == 4 { cCycles &-= 1 }
        remdays &-= cCycles &* .daysPer100Years

         
         
        var qCycles = remdays / .daysPer4Years
        if qCycles == 25 { qCycles &-= 1 }
        remdays &-= qCycles &* .daysPer4Years

         
         
        var remyears = remdays / .daysPerYear
        if remyears == 4 { remyears &-= 1 }
        remdays &-= remyears &* .daysPerYear

         
         
        var years = remyears + (4 &* qCycles) + (100 &* cCycles) + (400 &* qcCycles)

        var months = 0
        while Int64.daysInMonth(months) <= remdays {
            remdays -= Int64.daysInMonth(months)

             
             
            months &+= 1
        }

         
         
         
        if months >= 10 {
            months &-= 12
            years += 1
        }

         
         
         
         
         
         
         
        return (
            year: Int(years + 2000),
            month: Int(months &+ 3),
            day: Int(remdays &+ 1),
            hours: Int(remsecs / 3600),
            minutes: Int(remsecs / 60 % 60),
            seconds: Int(remsecs % 60)
        )
    }

    @inlinable
    init(timestampFromUTCDate date: (year: Int, month: Int, day: Int, hours: Int, minutes: Int, seconds: Int)) {
        assert((1...12).contains(date.month))
        assert((0...31).contains(date.day))
        assert((0..<24).contains(date.hours))
        assert((0..<60).contains(date.minutes))
        assert((0..<61).contains(date.seconds))

         
         
        var (seconds, isLeap) = Self.yearToSeconds(Int64(date.year) - 1900)
        seconds += Self.monthToSeconds(Int64(date.month) - 1, isLeap: isLeap)

         
         
        seconds += .secondsPerDay * (Int64(date.day) - 1)
        seconds += 3600 * Int64(date.hours)
        seconds += 60 * Int64(date.minutes)
        seconds += Int64(date.seconds)

        self = seconds
    }

    @inlinable
    static func yearToSeconds(_ year: Int64) -> (seconds: Int64, isLeap: Bool) {
        var (cycles, rem) = (year - 100).quotientAndRemainder(dividingBy: 400)
        if rem < 0 {
             
             
            cycles &-= 1
            rem &+= 400
        }

        let centuries: Int64
        let isLeap: Bool
        var leaps: Int64

        if rem == 0 {
            isLeap = true
            centuries = 0
            leaps = 0
        } else {
            switch rem {
            case 300...:
                centuries = 3
                rem &-= 300
            case 200...:
                centuries = 2
                rem &-= 200
            case 100...:
                centuries = 1
                rem &-= 100
            default:
                assert(rem > 0)
                centuries = 0
            }

            if rem == 0 {
                isLeap = false
                leaps = 0
            } else {
                (leaps, rem) = rem.quotientAndRemainder(dividingBy: 4)
                isLeap = (rem == 0)
            }
        }

        leaps += (97 * cycles) + (24 * centuries) - (isLeap ? 1 : 0)
        return (
            seconds: ((year - 100) * .secondsPerYear) + (leaps * .secondsPerDay) + .secondsFromEpochToYear2000
                + .secondsPerDay, isLeap: isLeap
        )
    }

    @inlinable
    static func monthToSeconds(_ month: Int64, isLeap: Bool) -> Int64 {
        var secondsThroughMonth: Int64

         
        switch month {
        case 0:
            secondsThroughMonth = 0
        case 1:
            secondsThroughMonth = 31 * .secondsPerDay
        case 2:
            secondsThroughMonth = 59 * .secondsPerDay
        case 3:
            secondsThroughMonth = 90 * .secondsPerDay
        case 4:
            secondsThroughMonth = 120 * .secondsPerDay
        case 5:
            secondsThroughMonth = 151 * .secondsPerDay
        case 6:
            secondsThroughMonth = 181 * .secondsPerDay
        case 7:
            secondsThroughMonth = 212 * .secondsPerDay
        case 8:
            secondsThroughMonth = 243 * .secondsPerDay
        case 9:
            secondsThroughMonth = 273 * .secondsPerDay
        case 10:
            secondsThroughMonth = 304 * .secondsPerDay
        case 11:
            secondsThroughMonth = 334 * .secondsPerDay
        default:
            fatalError("Invalid month: \(month)")
        }

        if isLeap && month >= 2 {
             
            secondsThroughMonth &+= .secondsPerDay
        }

        return secondsThroughMonth
    }
}
