import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class Venu3FaceView extends WatchUi.WatchFace {

    // True while the watch is in always-on (low power) mode
    private var _isLowPower as Boolean = false;

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

        var timeStr = getTimeString();

        if (_isLowPower) {
            drawLowPower(dc, timeStr, cx, cy);
            return;
        }

        var accent = getAccentColor();

        drawBatteryRing(dc, cx, cy, accent);

        // Date, e.g. "SAT 22 NOV"
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper();
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.22, Graphics.FONT_SMALL, dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Time
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_NUMBER_THAI_HOT, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Steps and heart rate
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.68, Graphics.FONT_TINY, getStepsString() + " steps", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.76, Graphics.FONT_TINY, getHeartRateString() + " bpm", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Venu 3 is AMOLED: in always-on mode keep lit pixels under 10% and
    // move content every minute to avoid burn-in.
    private function drawLowPower(dc as Dc, timeStr as String, cx as Number, cy as Number) as Void {
        var min = System.getClockTime().min;
        var offsetX = ((min % 5) - 2) * 6;
        var offsetY = (((min / 5) % 5) - 2) * 6;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + offsetX, cy + offsetY, Graphics.FONT_NUMBER_MEDIUM, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawBatteryRing(dc as Dc, cx as Number, cy as Number, accent as Number) as Void {
        var penWidth = 8;
        var radius = cx - penWidth;
        var battery = System.getSystemStats().battery;

        dc.setPenWidth(penWidth);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, radius);

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        if (battery >= 99.5) {
            dc.drawCircle(cx, cy, radius);
        } else if (battery > 0) {
            // Clockwise from 12 o'clock
            var endAngle = 90 - (360 * battery / 100).toNumber();
            dc.drawArc(cx, cy, radius, Graphics.ARC_CLOCKWISE, 90, endAngle);
        }
        dc.setPenWidth(1);
    }

    private function getTimeString() as String {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour, clock.min.format("%02d")]);
    }

    private function getStepsString() as String {
        var steps = ActivityMonitor.getInfo().steps;
        return steps != null ? steps.toString() : "--";
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
