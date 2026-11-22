import Toybox.Lang;

// Sample data used when Config.DEMO is true
module Demo {

    const CALORIES = 1846;

    // 51 minutes of heart rate: resting, a hard effort peaking above 120, then a cool-down
    function heartRateBars() as Array<Number?> {
        return [58, 61, 64, 70, 75, 82, 90, 98, 105, 112, 118, 124, 131, 138, 142, 141, 136,
                129, 121, 114, 106, 98, 91, 86, 82, 79, 76, 74, 72, 70, 68, 66, 65, 64] as Array<Number?>;
    }

    // 42 minutes of stress: calm, rising, a gap while active (no reading), then recovery
    function stressBars() as Array<Number?> {
        return [18, 22, 25, 30, 34, 41, 48, 55, 62, 70, 78, 82, 76, 68,
                null, null, null, null, 45, 40, 36, 31, 27, 24, 20, 22, 26, 21] as Array<Number?>;
    }

    // Last 7 days of [moderate, vigorous] minutes, oldest first, today last
    function last7Days() as Array<Array<Number>?> {
        return [[25, 5], [10, 0], [30, 15], [0, 0], [20, 10], [35, 0], [12, 4]] as Array<Array<Number>?>;
    }
}
