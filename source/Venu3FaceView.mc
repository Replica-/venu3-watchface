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

    // Graphs cover the last hour, averaged into 3-minute bars
    // (stress is only sampled about every 3 minutes)
    const GRAPH_MINUTES = 60;
    const GRAPH_BARS = 20;

    // Every piece of text except the clock uses one scalable font at this pixel size
    const TEXT_FONT_SIZE = 30;

    // Pixel sizes of the scalable time fonts
    const TIME_FONT_SIZE = 175;
    const SECONDS_FONT_SIZE = 64;

    // Fraction of the font's line height covered above (and below) the center by digit glyphs
    const GLYPH_HALF = 0.3;

    const COLOR_HR = 0xFF2255;
    const COLOR_TRACK = 0x333333;

    // Pale tint of the accent: top of the clock gradient and the colour of all plain text
    const PALE_MIX = 0.8;
    private var _pale as Number = 0xCCEEFF;

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
        var accent = getAccentColor();
        _pale = blendColor(accent, 0xFFFFFF, PALE_MIX);

        drawBorder(dc, cx, cy, accent);

        drawWeather(dc, cx, h * 0.12);

        drawStats(dc, cx, h * 0.215, activity);

        drawIntensity(dc, cx, (h * 0.275).toNumber(), activity, accent);

        drawDivider(dc, cx, h * 0.345, 120, accent);

        // Time sits in the exact center of the screen
        drawTime(dc, cx, cy, timeStr, clock.sec, accent);

        drawDivider(dc, cx, h * 0.625, 140, accent);

        // Heart rate and stress graphs below the time
        var graphW = 240;
        var graphH = 44;
        drawGraph(dc, cx - graphW / 2, (h * 0.645).toNumber(), graphW, graphH, _hrBars, false);
        drawGraph(dc, cx - graphW / 2, (h * 0.76).toNumber(), graphW, graphH, _stressBars, true);
    }

    // Accent ring around the edge with a faint inner ring and diamonds at 12, 3, 6 and 9
    private function drawBorder(dc as Dc, cx as Number, cy as Number, accent as Number) as Void {
        var r = cx - 4;
        dc.setPenWidth(3);
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        dc.setPenWidth(1);
        dc.setColor(blendColor(accent, 0x000000, 0.6), Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r - 7);

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        var d = r - 4;
        var s = 6;
        var points = [[cx, cy - d], [cx + d, cy], [cx, cy + d], [cx - d, cy]];
        for (var i = 0; i < points.size(); i++) {
            var px = points[i][0];
            var py = points[i][1];
            dc.fillPolygon([[px, py - s], [px + s, py], [px, py + s], [px - s, py]]);
        }
    }

    // Thin line that fades out towards both ends, with a small diamond in the middle
    private function drawDivider(dc as Dc, cx as Number, y as Numeric, half as Number, color as Number) as Void {
        var steps = 12;
        var stepW = half.toFloat() / steps;
        for (var i = 0; i < steps; i++) {
            dc.setColor(blendColor(color, 0x000000, 0.35 + 0.65 * i / steps), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx + 8 + i * stepW, y - 1, stepW + 1, 2);
            dc.fillRectangle(cx - 8 - (i + 1) * stepW, y - 1, stepW + 1, 2);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, y - 5], [cx + 5, y], [cx, y + 5], [cx - 5, y]]);
    }

    // Heart rate on the left, battery in the middle, calories on the right
    private function drawStats(dc as Dc, cx as Number, y as Numeric, activity as ActivityMonitor.Info) as Void {
        var vcenter = Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(COLOR_HR, Graphics.COLOR_TRANSPARENT);
        drawHeart(dc, cx - 140, y, 9);
        dc.setColor(_pale, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 125, y, textFont(), getHeartRateString(), Graphics.TEXT_JUSTIFY_LEFT | vcenter);

        drawBattery(dc, cx, y);

        // Calories: lightning bolt and a compact number, e.g. "1.8k"
        var calStr = formatCalories(Config.DEMO ? Demo.CALORIES : activity.calories);
        var calRight = cx + 145;
        dc.setColor(_pale, Graphics.COLOR_TRANSPARENT);
        dc.drawText(calRight, y, textFont(), calStr, Graphics.TEXT_JUSTIFY_RIGHT | vcenter);
        dc.setColor(0xFFCC00, Graphics.COLOR_TRANSPARENT);
        drawBolt(dc, calRight - dc.getTextWidthInPixels(calStr, textFont()) - 12, y);
    }

    private function formatCalories(calories as Number?) as String {
        if (calories == null) {
            return "--";
        }
        if (calories < 1000) {
            return calories.toString();
        }
        return (calories / 1000.0).format("%.1f") + "k";
    }

    private function drawBolt(dc as Dc, x as Numeric, y as Numeric) as Void {
        dc.fillPolygon([[x + 3, y - 11], [x - 6, y + 2], [x, y + 2], [x - 3, y + 11], [x + 6, y - 2], [x, y - 2]]);
    }

    // Battery outline with a colored fill level
    private function drawBattery(dc as Dc, cx as Number, y as Numeric) as Void {
        var pct = System.getSystemStats().battery;
        var color = pct > 50 ? 0x00CC44 : (pct > 20 ? 0xFFCC00 : 0xFF2200);
        var bw = 30;
        var bh = 16;
        var bx = cx - bw / 2;
        var by = y - bh / 2;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(bx, by, bw, bh, 3);
        dc.setPenWidth(1);
        dc.fillRectangle(bx + bw, by + 4, 3, bh - 8);

        var fillW = ((bw - 6) * pct / 100).toNumber();
        if (fillW > 0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + 3, by + 3, fillW, bh - 6);
        }
    }

    // ---------------------------------------------------------------- Time

    // Large gradient time. To its right, a narrow column: month and date on top,
    // smaller gradient seconds at the bottom.
    private function drawTime(dc as Dc, cx as Number, cy as Number, timeStr as String, sec as Number, accent as Number) as Void {
        loadTimeFonts();
        var font = _timeFont as Graphics.FontType;
        var secFont = _secondsFont as Graphics.FontType;
        var secStr = sec.format("%02d");

        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var monthStr = (info.month as String).toUpper();
        var dateStr = info.day.toString();

        var fh = dc.getFontHeight(font);
        var tw = dc.getTextWidthInPixels(timeStr, font);
        var sw = dc.getTextWidthInPixels(secStr, secFont);
        var colW = sw;
        var dateFont = textFont();
        var monthW = dc.getTextWidthInPixels(monthStr, dateFont);
        colW = monthW > colW ? monthW : colW;
        var secGap = 4;
        // The big digits are centered; the column hangs off to the right.
        // If a wide time would push the column into the border ring, shift left just enough.
        var left = cx - tw / 2;
        var maxRight = cx + 200;
        if (left + tw + secGap + colW > maxRight) {
            left = maxRight - (tw + secGap + colW);
        }
        var colX = left + tw + secGap;

        drawGradientText(dc, left, cy, font, timeStr, tw, accent, 4);

        // Month and date line up with the top of the big digits
        var glyphTop = cy - fh * GLYPH_HALF;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colX + 2, glyphTop + 10, dateFont, monthStr, justify);
        dc.drawText(colX + 2, glyphTop + 38, dateFont, dateStr, justify);

        // Seconds share the baseline of the big digits, same style at a smaller scale
        var sfh = dc.getFontHeight(secFont);
        var secY = (cy + fh * GLYPH_HALF - sfh * GLYPH_HALF).toNumber();
        drawGradientText(dc, colX, secY, secFont, secStr, sw, accent, 2);
    }

    // Text with a drop shadow and a vertical gradient from a light tint of the accent color into the accent color.
    // The gradient is made by drawing the text once per horizontal band, clipped to that band.
    private function drawGradientText(dc as Dc, left as Number, cy as Number, font as Graphics.FontType,
            text as String, tw as Number, accent as Number, shadow as Number) as Void {
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var fh = dc.getFontHeight(font);

        dc.setColor(blendColor(accent, 0x000000, 0.65), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + shadow, cy + shadow, font, text, justify);

        // Digits only fill the middle part of the font's line height
        var glyphTop = cy - fh * GLYPH_HALF;
        var glyphH = fh * 2 * GLYPH_HALF;
        var band = fh > 100 ? 4 : 2;
        var topColor = _pale;
        for (var y = cy - fh / 2; y < cy + fh / 2; y += band) {
            var t = (y - glyphTop) / glyphH;
            t = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
            dc.setClip(left - 2, y, tw + 4, band);
            dc.setColor(blendColor(topColor, accent, t.toFloat()), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, cy, font, text, justify);
        }
        dc.clearClip();
    }

    // Scaled-up versions of the system number font, bigger than any built-in size.
    // Fall back to built-in fonts on devices without scalable fonts.
    private var _timeFont as Graphics.FontType? = null;
    private var _secondsFont as Graphics.FontType? = null;

    private var _textFont as Graphics.FontType? = null;

    // The shared text font, falling back to the built-in "tiny" size
    private function textFont() as Graphics.FontType {
        if (_textFont == null) {
            _textFont = Graphics.FONT_TINY;
            if (Graphics has :getVectorFont) {
                var tf = Graphics.getVectorFont({:face => "RobotoRegular", :size => TEXT_FONT_SIZE});
                if (tf != null) {
                    _textFont = tf;
                }
            }
        }
        return _textFont as Graphics.FontType;
    }

    private function loadTimeFonts() as Void {
        if (_timeFont != null) {
            return;
        }
        _timeFont = Graphics.FONT_NUMBER_THAI_HOT;
        _secondsFont = Graphics.FONT_NUMBER_MILD;
        if (Graphics has :getVectorFont) {
            var vf = Graphics.getVectorFont({:face => "YantramanavRegular", :size => TIME_FONT_SIZE});
            if (vf != null) {
                _timeFont = vf;
            }
            var sf = Graphics.getVectorFont({:face => "YantramanavRegular", :size => SECONDS_FONT_SIZE});
            if (sf != null) {
                _secondsFont = sf;
            }
        }
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

    // One row: icon, temperature, wind
    private function drawWeather(dc as Dc, cx as Number, y as Numeric) as Void {
        if (!(Toybox has :Weather)) {
            return;
        }
        var vcenter = Graphics.TEXT_JUSTIFY_VCENTER;
        var cond = Weather.getCurrentConditions();
        if (cond == null) {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y, textFont(), "NO WEATHER", Graphics.TEXT_JUSTIFY_CENTER | vcenter);
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

        // Wind speed as a bare number, in km/h or mph to match the watch's units
        var windStr = "--";
        var speed = cond.windSpeed;
        if (speed != null) {
            windStr = Math.round(speed * (settings.distanceUnits == System.UNIT_STATUTE ? 2.237 : 3.6)).toNumber().toString();
        }

        // Center the whole row
        var iconW = 44;
        var gap = 18;
        var windIconW = 30;
        var tempW = dc.getTextWidthInPixels(tempStr, textFont());
        var windW = dc.getTextWidthInPixels(windStr, textFont());
        var x = cx - (iconW + tempW + gap + windIconW + windW) / 2;

        drawWeatherIcon(dc, x + 20, y, 18, getWeatherKind(cond.condition));
        dc.setColor(_pale, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + iconW, y, textFont(), tempStr, Graphics.TEXT_JUSTIFY_LEFT | vcenter);

        var windX = x + iconW + tempW + gap;
        drawWindIcon(dc, windX, y);
        dc.drawText(windX + windIconW, y, textFont(), windStr, Graphics.TEXT_JUSTIFY_LEFT | vcenter);
    }

    // Three gusts, the outer two curling at the end
    private function drawWindIcon(dc as Dc, x as Numeric, y as Numeric) as Void {
        dc.setPenWidth(3);
        dc.drawLine(x, y - 7, x + 16, y - 7);
        dc.drawArc(x + 16, y - 11, 4, Graphics.ARC_COUNTER_CLOCKWISE, 270, 180);
        dc.drawLine(x + 3, y, x + 22, y);
        dc.drawLine(x, y + 7, x + 12, y + 7);
        dc.drawArc(x + 12, y + 11, 4, Graphics.ARC_CLOCKWISE, 90, 180);
        dc.setPenWidth(1);
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
        if (Config.DEMO) {
            _hrBars = Demo.heartRateBars();
            _stressBars = Demo.stressBars();
            return;
        }
        _hrBars = [] as Array<Number?>;
        _stressBars = [] as Array<Number?>;
        if (!(Toybox has :SensorHistory)) {
            return;
        }
        var options = {:period => new Time.Duration(GRAPH_MINUTES * 60)};
        if (SensorHistory has :getHeartRateHistory) {
            _hrBars = bucketHistory(SensorHistory.getHeartRateHistory(options));
        }
        if (SensorHistory has :getStressHistory) {
            _stressBars = bucketHistory(SensorHistory.getStressHistory(options));
        }
    }

    // Averages samples into GRAPH_BARS time slots, oldest first. Empty slots are null.
    private function bucketHistory(iter as SensorHistory.SensorHistoryIterator) as Array<Number?> {
        var span = GRAPH_MINUTES * 60;
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
            bars as Array<Number?>, isStress as Boolean) as Void {
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

        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, y + gh, x + gw, y + gh);

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
            dc.setColor(isStress ? getStressColor(v) : getHeartRateColor(v), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x + i * barW, y + gh - barH, barW - 1, barH);
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

    // Gradient from green (60 bpm and below) through yellow (90) to red (120); purple above 120
    private function getHeartRateColor(v as Number) as Number {
        if (v > 120) {
            return 0xAA33FF;
        }
        if (v <= 60) {
            return 0x00CC44;
        }
        if (v <= 90) {
            return blendColor(0x00CC44, 0xFFCC00, (v - 60) / 30.0);
        }
        return blendColor(0xFFCC00, 0xFF2200, (v - 90) / 30.0);
    }

    // Linear blend between two RGB colors, t from 0.0 (a) to 1.0 (b)
    private function blendColor(a as Number, b as Number, t as Float) as Number {
        var r = ((a >> 16) & 0xFF) + ((((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t).toNumber();
        var g = ((a >> 8) & 0xFF) + ((((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t).toNumber();
        var bl = (a & 0xFF) + (((b & 0xFF) - (a & 0xFF)) * t).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    // ---------------------------------------------------------------- Intensity minutes

    // Rolling 7 days: one block per day (today on the right), each filling towards
    // 1/7 of the weekly goal with moderate then vigorous minutes
    // (vigorous minutes count double, as Garmin counts them). Colours match the clock
    // gradient: moderate in the light tint, vigorous in the full accent.
    private function drawIntensity(dc as Dc, cx as Number, y as Number, info as ActivityMonitor.Info, accent as Number) as Void {
        var goal = info.activeMinutesWeekGoal;
        if (goal == null || goal <= 0) {
            goal = 150;
        }
        var dailyTarget = (goal + 6) / 7;
        var days = getLast7Days(info);
        var lightAccent = _pale;

        var blockW = 30;
        var blockH = 14;
        var gap = 4;
        var x = cx - (7 * blockW + 6 * gap) / 2;

        for (var i = 0; i < 7; i++) {
            var am = days[i];
            var bx = x + i * (blockW + gap);
            dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(bx, y, blockW, blockH, 3);

            if (am != null) {
                // Past the daily target the block is full, split in proportion
                var moderate = am[0];
                var vigorous = 2 * am[1];
                var scale = moderate + vigorous > dailyTarget ? moderate + vigorous : dailyTarget;
                var modW = moderate * blockW / scale;
                var vigW = vigorous * blockW / scale;
                if (modW > 0) {
                    dc.setColor(lightAccent, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(bx, y, modW, blockH, 3);
                }
                if (vigW > 0) {
                    dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
                    dc.fillRoundedRectangle(bx + modW, y, vigW, blockH, 3);
                }
            }
        }

        // Outline today's block
        dc.setColor(lightAccent, Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x + 6 * (blockW + gap) - 2, y - 2, blockW + 4, blockH + 4, 4);
    }

    // [moderate, vigorous] minutes for the last 7 days, oldest first, today last. Missing days are null.
    private function getLast7Days(info as ActivityMonitor.Info) as Array<Array<Number>?> {
        if (Config.DEMO) {
            return Demo.last7Days();
        }
        var days = new Array<Array<Number>?>[7];
        var history = ActivityMonitor.getHistory();
        if (history != null) {
            // history[0] is yesterday
            for (var i = 0; i < 6 && i < history.size(); i++) {
                days[5 - i] = toPair(history[i].activeMinutes);
            }
        }
        days[6] = toPair(info.activeMinutesDay);
        return days;
    }

    private function toPair(am as ActivityMonitor.ActiveMinutes?) as Array<Number>? {
        return am != null ? [am.moderate, am.vigorous] as Array<Number> : null;
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
        return Lang.format("$1$:$2$", [hour.format("%02d"), clock.min.format("%02d")]);
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
