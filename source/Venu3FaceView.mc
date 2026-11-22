import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

class Venu3FaceView extends WatchUi.WatchFace {

    // Graphs cover the last few hours, averaged into this many bars
    const GRAPH_HOURS = 4;
    const GRAPH_BARS = 40;

    const COLOR_MODERATE = 0xFFAA00;
    const COLOR_VIGOROUS = 0xFF3300;
    const COLOR_HR = 0xFF2255;
    const COLOR_TRACK = 0x333333;

    // True while the watch is in always-on (low power) mode
    private var _isLowPower as Boolean = false;

    // Graph data is cached and only rebuilt once a minute
    private var _graphMinute as Number = -1;
    private var _hrBars as Array<Number?> = [] as Array<Number?>;
    private var _stressBars as Array<Number?> = [] as Array<Number?>;

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var clock = System.getClockTime();
        var timeStr = getTimeString(clock);

        if (_isLowPower) {
            drawLowPower(dc, timeStr, clock.min, cx, cy);
            return;
        }

        if (clock.min != _graphMinute) {
            refreshGraphs();
            _graphMinute = clock.min;
        }

        var activity = ActivityMonitor.getInfo();
        var weekGoal = activity.activeMinutesWeekGoal;
        if (weekGoal == null || weekGoal <= 0) {
            weekGoal = 150;
        }

        drawWeeklyRing(dc, cx, cy, activity, weekGoal);
        drawWeather(dc, cx, h * 0.12, h * 0.20);

        // Date, e.g. "SAT 22 NOV"
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper();
        dc.setColor(getAccentColor(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.27, Graphics.FONT_XTINY, dateStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Time
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.385, Graphics.FONT_NUMBER_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Heart rate and calories
        var statsY = h * 0.50;
        dc.setColor(COLOR_HR, Graphics.COLOR_TRANSPARENT);
        drawHeart(dc, cx - 95, statsY, 9);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 78, statsY, Graphics.FONT_TINY, getHeartRateString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        var calories = activity.calories;
        dc.drawText(cx + 20, statsY, Graphics.FONT_TINY, (calories != null ? calories.toString() : "--"), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 20 + dc.getTextWidthInPixels((calories != null ? calories.toString() : "--") + " ", Graphics.FONT_TINY), statsY + 3,
            Graphics.FONT_XTINY, "kcal", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Heart rate and stress graphs
        var graphW = 150;
        var graphH = 48;
        var graphY = (h * 0.577).toNumber();
        drawGraph(dc, cx - graphW - 8, graphY, graphW, graphH, _hrBars, false, "HR");
        drawGraph(dc, cx + 8, graphY, graphW, graphH, _stressBars, true, "STRESS");

        drawTodayIntensity(dc, cx, h * 0.775, activity.activeMinutesDay, weekGoal);
    }

    // ---------------------------------------------------------------- Low power

    // Venu 3 is AMOLED: in always-on mode keep lit pixels under 10% and
    // move content every minute to avoid burn-in.
    private function drawLowPower(dc as Dc, timeStr as String, min as Number, cx as Number, cy as Number) as Void {
        var offsetX = ((min % 5) - 2) * 6;
        var offsetY = (((min / 5) % 5) - 2) * 6;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + offsetX, cy + offsetY, Graphics.FONT_NUMBER_MEDIUM, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---------------------------------------------------------------- Weather

    private function drawWeather(dc as Dc, cx as Number, iconY as Numeric, windY as Numeric) as Void {
        if (!(Toybox has :Weather)) {
            return;
        }
        var cond = Weather.getCurrentConditions();
        if (cond == null) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, iconY, Graphics.FONT_XTINY, "NO WEATHER", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        var settings = System.getDeviceSettings();

        var tempStr = "--°";
        var temp = cond.temperature;
        if (temp != null) {
            if (settings.temperatureUnits == System.UNIT_STATUTE) {
                temp = temp * 1.8 + 32;
            }
            tempStr = Math.round(temp).toNumber().toString() + "°";
        }

        drawWeatherIcon(dc, cx - 40, iconY, 20, getWeatherKind(cond.condition));
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 10, iconY, Graphics.FONT_TINY, tempStr, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        var speed = cond.windSpeed;
        if (speed != null) {
            var windStr = settings.distanceUnits == System.UNIT_STATUTE
                ? Math.round(speed * 2.237).toNumber() + " mph"
                : Math.round(speed * 3.6).toNumber() + " km/h";
            var bearing = cond.windBearing;
            if (bearing != null) {
                windStr = getCompassPoint(bearing) + " " + windStr;
            }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, windY, Graphics.FONT_XTINY, windStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function getCompassPoint(bearing as Number) as String {
        var points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return points[((bearing + 22) % 360) / 45];
    }

    // Groups Garmin's many weather conditions into the icons we can draw
    private function getWeatherKind(condition as Number?) as Symbol {
        if (condition == null) {
            return :cloud;
        }
        if ([Weather.CONDITION_CLEAR, Weather.CONDITION_MOSTLY_CLEAR, Weather.CONDITION_FAIR].indexOf(condition) >= 0) {
            return :sun;
        }
        if ([Weather.CONDITION_PARTLY_CLOUDY, Weather.CONDITION_PARTLY_CLEAR, Weather.CONDITION_THIN_CLOUDS].indexOf(condition) >= 0) {
            return :partly;
        }
        if ([Weather.CONDITION_THUNDERSTORMS, Weather.CONDITION_SCATTERED_THUNDERSTORMS,
             Weather.CONDITION_CHANCE_OF_THUNDERSTORMS, Weather.CONDITION_TROPICAL_STORM,
             Weather.CONDITION_HURRICANE, Weather.CONDITION_TORNADO].indexOf(condition) >= 0) {
            return :storm;
        }
        if ([Weather.CONDITION_SNOW, Weather.CONDITION_LIGHT_SNOW, Weather.CONDITION_HEAVY_SNOW,
             Weather.CONDITION_CHANCE_OF_SNOW, Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW,
             Weather.CONDITION_FLURRIES, Weather.CONDITION_ICE_SNOW, Weather.CONDITION_WINTRY_MIX,
             Weather.CONDITION_RAIN_SNOW, Weather.CONDITION_LIGHT_RAIN_SNOW, Weather.CONDITION_HEAVY_RAIN_SNOW,
             Weather.CONDITION_CHANCE_OF_RAIN_SNOW, Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW,
             Weather.CONDITION_SLEET, Weather.CONDITION_HAIL, Weather.CONDITION_ICE].indexOf(condition) >= 0) {
            return :snow;
        }
        if ([Weather.CONDITION_RAIN, Weather.CONDITION_LIGHT_RAIN, Weather.CONDITION_HEAVY_RAIN,
             Weather.CONDITION_SHOWERS, Weather.CONDITION_LIGHT_SHOWERS, Weather.CONDITION_HEAVY_SHOWERS,
             Weather.CONDITION_SCATTERED_SHOWERS, Weather.CONDITION_CHANCE_OF_SHOWERS,
             Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN, Weather.CONDITION_DRIZZLE,
             Weather.CONDITION_FREEZING_RAIN, Weather.CONDITION_UNKNOWN_PRECIPITATION].indexOf(condition) >= 0) {
            return :rain;
        }
        return :cloud;
    }

    private function drawWeatherIcon(dc as Dc, x as Number, y as Numeric, r as Number, kind as Symbol) as Void {
        if (kind == :sun) {
            drawSun(dc, x, y, r);
        } else if (kind == :partly) {
            drawSun(dc, x + r / 3, y - r / 3, r * 3 / 4);
            drawCloud(dc, x - r / 6, y + r / 4, r * 3 / 4, Graphics.COLOR_LT_GRAY);
        } else if (kind == :cloud) {
            drawCloud(dc, x, y, r, Graphics.COLOR_LT_GRAY);
        } else {
            // Rain, snow and storms: a darker cloud with something falling from it
            drawCloud(dc, x, y - r / 3, r, Graphics.COLOR_DK_GRAY);
            var top = y + r / 3;
            if (kind == :rain) {
                dc.setColor(0x3399FF, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
                for (var i = -1; i <= 1; i++) {
                    var dx = x + i * r / 2;
                    dc.drawLine(dx + 3, top, dx - 2, top + r / 2);
                }
                dc.setPenWidth(1);
            } else if (kind == :snow) {
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                for (var i = -1; i <= 1; i++) {
                    dc.fillCircle(x + i * r / 2, top + r / 4 + (i == 0 ? r / 4 : 0), 3);
                }
            } else {
                dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon([[x + 2, top - 2], [x - 6, top + r / 3], [x, top + r / 3],
                                [x - 4, top + r * 2 / 3], [x + 7, top + r / 4], [x + 1, top + r / 4]]);
            }
        }
    }

    private function drawSun(dc as Dc, x as Numeric, y as Numeric, r as Number) as Void {
        dc.setColor(0xFFCC00, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r / 2);
        dc.setPenWidth(2);
        for (var i = 0; i < 8; i++) {
            var a = i * Math.PI / 4;
            var cosA = Math.cos(a);
            var sinA = Math.sin(a);
            dc.drawLine(x + cosA * r * 0.7, y + sinA * r * 0.7, x + cosA * r, y + sinA * r);
        }
        dc.setPenWidth(1);
    }

    private function drawCloud(dc as Dc, x as Numeric, y as Numeric, r as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r * 0.45, y + r * 0.15, r * 0.4);
        dc.fillCircle(x + r * 0.05, y - r * 0.1, r * 0.55);
        dc.fillCircle(x + r * 0.55, y + r * 0.2, r * 0.35);
        dc.fillRectangle(x - r * 0.45, y + r * 0.1, r, r * 0.45);
    }

    // ---------------------------------------------------------------- Graphs

    private function refreshGraphs() as Void {
        _hrBars = [] as Array<Number?>;
        _stressBars = [] as Array<Number?>;
        if (!(Toybox has :SensorHistory)) {
            return;
        }
        var options = {:period => new Time.Duration(GRAPH_HOURS * 3600)};
        if (SensorHistory has :getHeartRateHistory) {
            _hrBars = bucketHistory(SensorHistory.getHeartRateHistory(options));
        }
        if (SensorHistory has :getStressHistory) {
            _stressBars = bucketHistory(SensorHistory.getStressHistory(options));
        }
    }

    // Averages samples into GRAPH_BARS time slots, oldest first. Empty slots are null.
    private function bucketHistory(iter as SensorHistory.SensorHistoryIterator) as Array<Number?> {
        var span = GRAPH_HOURS * 3600;
        var start = Time.now().value() - span;
        var sums = new Array<Number>[GRAPH_BARS];
        var counts = new Array<Number>[GRAPH_BARS];
        for (var i = 0; i < GRAPH_BARS; i++) {
            sums[i] = 0;
            counts[i] = 0;
        }

        var sample = iter.next();
        while (sample != null) {
            var value = sample.data;
            var when = sample.when;
            if (value != null && when != null) {
                var slot = (when.value() - start) * GRAPH_BARS / span;
                if (slot >= 0 && slot < GRAPH_BARS) {
                    sums[slot] += value.toNumber();
                    counts[slot] += 1;
                }
            }
            sample = iter.next();
        }

        var bars = new Array<Number?>[GRAPH_BARS];
        for (var j = 0; j < GRAPH_BARS; j++) {
            bars[j] = counts[j] > 0 ? sums[j] / counts[j] : null;
        }
        return bars;
    }

    private function drawGraph(dc as Dc, x as Number, y as Number, gw as Number, gh as Number,
            bars as Array<Number?>, isStress as Boolean, label as String) as Void {
        // HR is auto-scaled to its own range; stress is always 0-100
        var lo = 0;
        var hi = 100;
        var latest = null;
        if (!isStress) {
            lo = 999;
            hi = 0;
        }
        for (var i = 0; i < bars.size(); i++) {
            var v = bars[i];
            if (v != null) {
                latest = v;
                if (!isStress) {
                    lo = v < lo ? v : lo;
                    hi = v > hi ? v : hi;
                }
            }
        }
        if (!isStress && latest != null) {
            lo -= 5;
            hi += 5;
        }

        // Label with latest value
        dc.setColor(isStress ? COLOR_MODERATE : COLOR_HR, Graphics.COLOR_TRANSPARENT);
        var labelX = isStress ? x : x + gw;
        var justify = isStress ? Graphics.TEXT_JUSTIFY_LEFT : Graphics.TEXT_JUSTIFY_RIGHT;
        dc.drawText(labelX, y, Graphics.FONT_XTINY,
            label + " " + (latest != null ? latest.toString() : "--"), justify | Graphics.TEXT_JUSTIFY_VCENTER);

        var top = y + 18;
        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, top + gh, x + gw, top + gh);

        if (latest == null || hi <= lo) {
            return;
        }

        var barW = gw.toFloat() / GRAPH_BARS;
        for (var i = 0; i < bars.size(); i++) {
            var v = bars[i];
            if (v == null) {
                continue;
            }
            var barH = (gh * (v - lo).toFloat() / (hi - lo)).toNumber();
            if (barH < 2) {
                barH = 2;
            }
            dc.setColor(isStress ? getStressColor(v) : COLOR_HR, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + i * barW, top + gh - barH, barW - 1, barH);
        }
    }

    // Same bands Garmin uses: rest / low / medium / high
    private function getStressColor(v as Number) as Number {
        if (v <= 25) {
            return 0x3399FF;
        } else if (v <= 50) {
            return 0xFFB366;
        } else if (v <= 75) {
            return 0xFF8000;
        }
        return 0xFF4D00;
    }

    // ---------------------------------------------------------------- Intensity minutes

    // Garmin counts each vigorous minute twice towards the goal
    private function weighted(am as ActivityMonitor.ActiveMinutes?) as Number {
        if (am == null) {
            return 0;
        }
        return am.moderate + 2 * am.vigorous;
    }

    // Today's total, plus a bar split into moderate and vigorous segments.
    // The bar is full when today reaches 1/7 of the weekly goal.
    private function drawTodayIntensity(dc as Dc, cx as Number, y as Numeric,
            today as ActivityMonitor.ActiveMinutes?, weekGoal as Number) as Void {
        var moderate = today != null ? today.moderate : 0;
        var vigorous = today != null ? 2 * today.vigorous : 0;
        var total = moderate + vigorous;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, "TODAY " + total + " MIN", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var bw = 160;
        var bh = 10;
        var bx = cx - bw / 2;
        var by = y + 20;
        var dailyTarget = (weekGoal + 6) / 7;

        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(bx, by, bw, bh, 4);

        var modW = moderate * bw / dailyTarget;
        if (modW > bw) {
            modW = bw;
        }
        var vigW = vigorous * bw / dailyTarget;
        if (modW + vigW > bw) {
            vigW = bw - modW;
        }
        if (modW > 0) {
            dc.setColor(COLOR_MODERATE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, by, modW, bh, 4);
        }
        if (vigW > 0) {
            dc.setColor(COLOR_VIGOROUS, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx + modW + (modW > 0 ? 2 : 0), by, vigW - (modW > 0 ? 2 : 0), bh, 4);
        }
    }

    // Ring around the edge: one segment per day this week, filling towards the weekly goal
    private function drawWeeklyRing(dc as Dc, cx as Number, cy as Number,
            info as ActivityMonitor.Info, weekGoal as Number) as Void {
        var pen = 10;
        var r = cx - pen / 2 - 2;
        dc.setPenWidth(pen);
        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);

        var days = getWeekDays(info);
        var degPerMin = 360.0 / weekGoal;
        var angle = 90.0;
        var remaining = 360.0;
        var weekTotal = 0;

        for (var i = 0; i < days.size(); i++) {
            var am = days[i];
            weekTotal += weighted(am);
            // Each day: moderate part then vigorous part, small gap after the day
            var parts = [[am.moderate, COLOR_MODERATE], [2 * am.vigorous, COLOR_VIGOROUS]];
            for (var p = 0; p < parts.size(); p++) {
                var sweep = (parts[p][0] as Number) * degPerMin;
                if (sweep > remaining) {
                    sweep = remaining;
                }
                if (sweep >= 1) {
                    dc.setColor(parts[p][1] as Number, Graphics.COLOR_TRANSPARENT);
                    dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, angle, angle - sweep);
                }
                angle -= sweep;
                remaining -= sweep;
            }
            if (weighted(am) > 0 && remaining > 2) {
                angle -= 2;
                remaining -= 2;
            }
        }
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy * 2 * 0.90, Graphics.FONT_XTINY, "WEEK " + weekTotal + "/" + weekGoal,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Active minutes for each day since the start of the week, oldest first, ending with today
    private function getWeekDays(info as ActivityMonitor.Info) as Array<ActivityMonitor.ActiveMinutes> {
        var result = [] as Array<ActivityMonitor.ActiveMinutes>;
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var firstDay = System.getDeviceSettings().firstDayOfWeek;
        var pastDays = ((today.day_of_week as Number) - firstDay + 7) % 7;

        var history = ActivityMonitor.getHistory();
        if (history != null) {
            for (var i = pastDays - 1; i >= 0; i--) {
                if (i < history.size()) {
                    var am = history[i].activeMinutes;
                    if (am != null) {
                        result.add(am);
                    }
                }
            }
        }
        if (info.activeMinutesDay != null) {
            result.add(info.activeMinutesDay);
        }
        return result;
    }

    // ---------------------------------------------------------------- Helpers

    private function drawHeart(dc as Dc, x as Numeric, y as Numeric, s as Number) as Void {
        dc.fillCircle(x - s / 2, y - s / 4, s / 2 + 1);
        dc.fillCircle(x + s / 2, y - s / 4, s / 2 + 1);
        dc.fillPolygon([[x - s - 1, y], [x + s + 1, y], [x, y + s]]);
    }

    private function getTimeString(clock as System.ClockTime) as String {
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour, clock.min.format("%02d")]);
    }

    private function getHeartRateString() as String {
        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null && activityInfo.currentHeartRate != null) {
            return activityInfo.currentHeartRate.toString();
        }

        // Fall back to the most recent sample from the daily HR history
        var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
        if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
            return sample.heartRate.toString();
        }
        return "--";
    }

    private function getAccentColor() as Number {
        var color = Application.Properties.getValue("AccentColor");
        return color instanceof Number ? color : Graphics.COLOR_BLUE;
    }

    function onExitSleep() as Void {
        _isLowPower = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _isLowPower = true;
        WatchUi.requestUpdate();
    }
}
