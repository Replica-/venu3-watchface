import Toybox.Lang;

// Sample data used when Config.DEMO is true
module Demo {

    const CALORIES = 1846;

    // An hour of heart rate: resting, a hard effort peaking above 120, then a cool-down
    function heartRateBars() as Array<Number?> {
        return [58, 59, 62, 66, 75, 90, 105, 118, 131, 142,
                136, 121, 106, 91, 82, 76, 72, 70, 67, 65] as Array<Number?>;
    }

    // An hour of stress: calm, rising, a gap while active (no reading), then recovery
    function stressBars() as Array<Number?> {
        return [18, 25, 34, 48, 62, 78, 82, 68, null, null,
                null, null, 45, 36, 27, 20, 22, 29, 27, 21] as Array<Number?>;
    }

    // Last 7 days of [moderate, vigorous] minutes, oldest first, today last
    function last7Days() as Array<Array<Number>?> {
        return [[25, 5], [10, 0], [30, 15], [0, 0], [20, 10], [35, 0], [12, 4]] as Array<Array<Number>?>;
    }
}
