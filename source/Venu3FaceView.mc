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
import Toybox.UserProfile;
import Toybox.Weather;
import Toybox.WatchUi;

class Venu3FaceView extends WatchUi.WatchFace {

    // Both graphs use 1.5-minute bars of the same pixel width on one shared grid so
    // their bars line up. Heart rate shows 51 minutes; the narrower stress graph 42.
    const BAR_SECONDS = 90;
    const BAR_PX = 8.25;
    const HR_BARS = 34;
    const STRESS_BARS = 28;

    // Height in pixels of every icon in the icon row, and that row's text size
    const ICON_H = 28;
    const ROW_FONT_SIZE = 34;

    // Other text (month, date) uses one scalable font at this pixel size
    const TEXT_FONT_SIZE = 30;

    // Pixel sizes of the scalable time fonts
    const TIME_FONT_SIZE = 180;
    // AM/PM and seconds share the height of the big digits, with a small gap between
    const SECONDS_FONT_SIZE = 74;
    const AMPM_FONT_SIZE = 74;

    // Fraction of the font's line height covered above (and below) the center by digit glyphs
    const GLYPH_HALF = 0.3;

    // Digit height and capital-letter height as fractions of the scalable font size
    const DIGIT_HEIGHT = 0.51;
    const CAP_HEIGHT = 0.71;

    const COLOR_TRACK = 0x333333;

    // Gradient colours, chosen in the watch face settings: _pale is the top of every
    // gradient and the colour of plain text, _accent the bottom of every gradient
    private var _pale as Number = 0xCCEEFF;
    private var _accent as Number = 0x00AAFF;

    // Graph colouring, chosen in the watch face settings: false = coloured zones,
    // true = the face's gradient colours
    private var _hrGradient as Boolean = false;
    private var _stressGradient as Boolean = true;

    // Colour ranges, from the watch face settings. Heart rate: green at or below _hrLow,
    // red at _hrHigh, purple above. Stress bands: rest / low / medium / high.
    private var _hrLow as Number = 60;
    private var _hrHigh as Number = 120;
    private var _stressRest as Number = 25;
    private var _stressLow as Number = 50;
    private var _stressMedium as Number = 75;

    // True while the watch is in always-on (low power) mode
    private var _isLowPower as Boolean = false;

    // Graph data is cached and only rebuilt once a minute
    private var _graphMinute as Number = -1;
    private var _hrBars as Array<Number?> = [] as Array<Number?>;
    private var _stressBars as Array<Number?> = [] as Array<Number?>;

    // Everything except the seconds only changes once a minute, so it is drawn into
    // this off-screen image once a minute; each second just copies it to the screen
    // and draws the seconds on top. Rebuilt when the minute changes or settings change.
    private var _frame as Graphics.BufferedBitmapReference? = null;
    private var _frameMinute as Number = -1;

    // Where the seconds go, worked out when the frame is drawn
    private var _secX as Number = 0;
    private var _secY as Number = 0;

    function initialize() {
        WatchFace.initialize();
    }

    // Called by the app when settings change, so the next update redraws everything
    function invalidate() as Void {
        _frameMinute = -1;
    }

    function onUpdate(dc as Dc) as Void {
        var clock = System.getClockTime();

        if (_isLowPower) {
            prepare(dc);
            drawLowPower(dc, getTimeString(clock), clock.min, dc.getWidth() / 2, dc.getHeight() / 2);
            return;
        }

        if (_frame == null && Graphics has :createBufferedBitmap) {
            _frame = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()});
        }

        var minute = clock.hour * 60 + clock.min;
        var frame = _frame != null ? _frame.get() : null;
        if (frame == null) {
            // No off-screen image available: draw everything straight to the screen
            drawFrame(dc, clock);
        } else {
            if (minute != _frameMinute) {
                drawFrame((frame as Graphics.BufferedBitmap).getDc(), clock);
                _frameMinute = minute;
            }
            dc.drawBitmap(0, 0, frame as Graphics.BufferedBitmap);
        }

        drawSeconds(dc, clock.sec);
    }

    private function prepare(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }

    // Draws everything except the seconds
    private function drawFrame(dc as Dc, clock as System.ClockTime) as Void {
        prepare(dc);
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2;
        var cy = h / 2;
        var timeStr = getTimeString(clock);

        if (clock.min != _graphMinute) {
            refreshGraphs();
            _graphMinute = clock.min;
        }

        var activity = ActivityMonitor.getInfo();
        applyColorMode(clock);
        _hrGradient = getColorSetting("HrGraphStyle", 0) == 1;
        _stressGradient = getColorSetting("StressGraphStyle", 1) == 1;
        loadRanges();
        var accent = _accent;

        drawBorder(dc, cx, cy, accent);

        drawIntensity(dc, cx, (h * 0.153).toNumber(), activity, accent);

        drawTopRow(dc, cx, h * 0.253, activity);

        drawDivider(dc, cx, h * 0.335, 120, accent);

        // Time sits in the exact center of the screen
        drawTime(dc, cx, cy, timeStr, clock.hour, accent);

        drawDivider(dc, cx, h * 0.665, 140, accent);

        // Heart rate and stress graphs below the time
        var graphH = 44;
        // Stress is centered on the heart rate bar slots so the bars line up column for column
        var hrLeft = cx - HR_BARS * BAR_PX / 2;
        drawGraph(dc, hrLeft, (h * 0.69).toNumber(), HR_BARS * BAR_PX, graphH, _hrBars, false);
        var stressLeft = hrLeft + (HR_BARS - STRESS_BARS) / 2 * BAR_PX;
        drawGraph(dc, stressLeft, (h * 0.8).toNumber(), STRESS_BARS * BAR_PX, graphH, _stressBars, true);

        drawDate(dc, cx, h * 0.09, accent);
    }

    // Solid ring around the edge in the clock gradient: pale at the top, accent at the bottom.
    // Drawn as short arcs, each coloured by its height.
    private function drawBorder(dc as Dc, cx as Number, cy as Number, accent as Number) as Void {
        var r = cx - 5;
        var step = 5;
        dc.setPenWidth(6);
        for (var a = 0; a < 360; a += step) {
            var t = (1 - Math.sin(Math.toRadians(a + step / 2.0))) / 2;
            dc.setColor(blendColor(_pale, accent, t.toFloat()), Graphics.COLOR_TRANSPARENT);
            // One degree of overlap so no gaps show between arcs
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, a, a + step + 1);
        }
        dc.setPenWidth(1);
    }

    // Gradient bar: pale in the middle, accent further out, fading to black at both ends
    private function drawDivider(dc as Dc, cx as Number, y as Numeric, half as Number, color as Number) as Void {
        var steps = 24;
        var stepW = half.toFloat() / steps;
        for (var i = 0; i < steps; i++) {
            var t = i.toFloat() / steps;
            var c = t < 0.5 ? blendColor(_pale, color, t * 2) : blendColor(color, 0x000000, (t - 0.5) * 2);
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(cx + i * stepW, y - 2, stepW + 1, 4);
            dc.fillRectangle(cx - (i + 1) * stepW, y - 2, stepW + 1, 4);
        }
    }

    // Draws an icon in the clock's pale-to-accent vertical gradient, by drawing it
    // once per thin horizontal band, clipped to that band
    private function drawGradientIcon(dc as Dc, kind as Symbol, x as Number, y as Numeric, half as Number) as Void {
        var top = y - half;
        for (var by = top; by < y + half; by += 2) {
            dc.setClip(x - 40, by, 80, 2);
            dc.setColor(blendColor(_pale, _accent, (by - top).toFloat() / (2 * half)), Graphics.COLOR_TRANSPARENT);
            if (kind == :heart) {
                drawHeart(dc, x, y - 1, ICON_H / 2);
            } else if (kind == :bolt) {
                drawBolt(dc, x, y, ICON_H / 22.0);
            } else if (kind == :wind) {
                drawWindIcon(dc, x, y, (ICON_H - 2) / 30.0); // minus the line thickness
            } else if (kind == :battery) {
                drawBatteryShape(dc, x, y);
            }
        }
        dc.clearClip();
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

    // Lightning bolt, 22px tall at scale 1
    private function drawBolt(dc as Dc, x as Numeric, y as Numeric, k as Float) as Void {
        dc.fillPolygon([[x + 3 * k, y - 11 * k], [x - 6 * k, y + 2 * k], [x, y + 2 * k],
                        [x - 3 * k, y + 11 * k], [x + 6 * k, y - 2 * k], [x, y - 2 * k]]);
    }

    // Upright battery: outline and fill level (rising from the bottom) in the clock
    // gradient; the fill turns red when low
    const BATTERY_W = 14;
    const BATTERY_H = 26;
    const BATTERY_LOW = 20;
    private var _batteryFillH as Number = 0;

    private function drawBattery(dc as Dc, cx as Number, y as Numeric) as Void {
        var pct = System.getSystemStats().battery;
        var fillH = ((BATTERY_H - 6) * pct / 100).toNumber();
        // Half-height of the icon including the cap on top
        var half = BATTERY_H / 2 + 4;
        if (pct <= BATTERY_LOW) {
            // Gradient outline only, then the fill in red
            _batteryFillH = 0;
            drawGradientIcon(dc, :battery, cx, y, half);
            if (fillH > 0) {
                dc.setColor(0xFF2200, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(cx - BATTERY_W / 2 + 3, y + BATTERY_H / 2 - 3 - fillH, BATTERY_W - 6, fillH);
            }
        } else {
            _batteryFillH = fillH;
            drawGradientIcon(dc, :battery, cx, y, half);
        }
    }

    private function drawBatteryShape(dc as Dc, cx as Number, y as Numeric) as Void {
        var bx = cx - BATTERY_W / 2;
        var by = y - BATTERY_H / 2;
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(bx, by, BATTERY_W, BATTERY_H, 3);
        dc.setPenWidth(1);
        dc.fillRectangle(cx - 3, by - 3, 6, 3);
        if (_batteryFillH > 0) {
            dc.fillRectangle(bx + 3, by + BATTERY_H - 3 - _batteryFillH, BATTERY_W - 6, _batteryFillH);
        }
    }

    // ---------------------------------------------------------------- Time

    // Large gradient time. To its right, a narrow column: AM/PM on top (12-hour mode
    // only) and the seconds at the bottom. The seconds are drawn separately each second
    // by drawSeconds; this works out where they go.
    private function drawTime(dc as Dc, cx as Number, cy as Number, timeStr as String,
            hour as Number, accent as Number) as Void {
        loadTimeFonts();
        var font = _timeFont as Graphics.FontType;
        var secFont = _secondsFont as Graphics.FontType;
        var ampmFont = _ampmFont as Graphics.FontType;
        var ampmStr = System.getDeviceSettings().is24Hour ? "" : (hour < 12 ? "AM" : "PM");

        var fh = dc.getFontHeight(font);
        var tw = dc.getTextWidthInPixels(timeStr, font);
        // A fixed width for the seconds, so the layout doesn't shift as they tick
        var sw = dc.getTextWidthInPixels("00", secFont);
        var aw = dc.getTextWidthInPixels(ampmStr, ampmFont);
        var colW = sw > aw ? sw : aw;
        var secGap = 6;
        // The whole block (time plus column) is centered on the screen
        var left = cx - (tw + secGap + colW) / 2;
        var colX = left + tw + secGap;

        drawGradientText(dc, left, cy, font, timeStr, tw, accent, 4);

        // Drawn vertically centered, the line box is centered on cy, so the baseline
        // (bottom of the digits) is the top of that box plus the font's ascent
        var baseline = cy - fh / 2 + Graphics.getFontAscent(font);
        var digitTop = baseline - TIME_FONT_SIZE * DIGIT_HEIGHT;

        // AM/PM top-aligned with the digits, in the same gradient style as the seconds
        if (!ampmStr.equals("")) {
            var afh = dc.getFontHeight(ampmFont);
            // Capital letters in this font stand a little taller than its digits
            var ampmBaseline = digitTop + AMPM_FONT_SIZE * DIGIT_HEIGHT + 2;
            var ampmY = (ampmBaseline - Graphics.getFontAscent(ampmFont) + afh / 2).toNumber();
            drawGradientText(dc, colX + 1, ampmY, ampmFont, ampmStr, aw, accent, 2);
        }

        // Seconds sit on the same baseline as the big digits, right-aligned with the
        // column (the right edge of AM/PM)
        var sfh = dc.getFontHeight(secFont);
        _secY = (baseline - Graphics.getFontAscent(secFont) + sfh / 2).toNumber();
        _secX = colX + colW;
    }

    // The seconds, drawn straight to the screen every second
    private function drawSeconds(dc as Dc, sec as Number) as Void {
        loadTimeFonts();
        var secFont = _secondsFont as Graphics.FontType;
        var secStr = sec.format("%02d");
        var sw = dc.getTextWidthInPixels(secStr, secFont);
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        drawGradientText(dc, _secX - sw, _secY, secFont, secStr, sw, _accent, 2);
    }

    // Month and date on one line, e.g. "NOV 22", in one gradient from pale at the
    // top of the capitals to accent at their bottom (drawn once per thin band),
    // with the battery to its right. The two are centered together.
    private function drawDate(dc as Dc, cx as Number, y as Numeric, accent as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = (info.month as String).toUpper() + " " + info.day;
        var font = textFont();
        var textW = dc.getTextWidthInPixels(dateStr, font);
        var gap = 12;
        var left = cx - (textW + gap + BATTERY_W) / 2;

        // Drawn from the top of the line box, placed so the capitals are centered on y
        var capH = TEXT_FONT_SIZE * CAP_HEIGHT;
        var gradTop = y - capH / 2;
        var textY = gradTop - (Graphics.getFontAscent(font) - capH);
        for (var by = gradTop.toNumber(); by < gradTop + capH; by += 2) {
            dc.setClip(left - 2, by, cx * 2, 2);
            dc.setColor(blendColor(_pale, accent, ((by - gradTop) / capH).toFloat()), Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, textY, font, dateStr, Graphics.TEXT_JUSTIFY_LEFT);
        }
        dc.clearClip();

        drawBattery(dc, left + textW + gap + BATTERY_W / 2, y + 1);
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
    private var _ampmFont as Graphics.FontType? = null;

    private var _textFont as Graphics.FontType? = null;
    private var _rowFont as Graphics.FontType? = null;

    // The shared text font, falling back to the built-in "tiny" size
    private function textFont() as Graphics.FontType {
        if (_textFont == null) {
            _textFont = loadFont(TEXT_FONT_SIZE, Graphics.FONT_TINY);
        }
        return _textFont as Graphics.FontType;
    }

    // The larger icon-row font, falling back to the built-in "small" size
    private function rowFont() as Graphics.FontType {
        if (_rowFont == null) {
            _rowFont = loadFont(ROW_FONT_SIZE, Graphics.FONT_SMALL);
        }
        return _rowFont as Graphics.FontType;
    }

    private function loadFont(size as Number, fallback as Graphics.FontType) as Graphics.FontType {
        if (Graphics has :getVectorFont) {
            var vf = Graphics.getVectorFont({:face => "RobotoRegular", :size => size});
            if (vf != null) {
                return vf;
            }
        }
        return fallback;
    }

    private function loadTimeFonts() as Void {
        if (_timeFont != null) {
            return;
        }
        _timeFont = Graphics.FONT_NUMBER_THAI_HOT;
        _secondsFont = Graphics.FONT_NUMBER_MILD;
        _ampmFont = Graphics.FONT_SMALL;
        if (Graphics has :getVectorFont) {
            var vf = Graphics.getVectorFont({:face => "YantramanavRegular", :size => TIME_FONT_SIZE});
            if (vf != null) {
                _timeFont = vf;
            }
            var sf = Graphics.getVectorFont({:face => "YantramanavRegular", :size => SECONDS_FONT_SIZE});
            if (sf != null) {
                _secondsFont = sf;
            }
            var af = Graphics.getVectorFont({:face => "YantramanavRegular", :size => AMPM_FONT_SIZE});
            if (af != null) {
                _ampmFont = af;
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

    // One centered row: weather and temperature, wind, heart rate, calories
    private function drawTopRow(dc as Dc, cx as Number, y as Numeric, activity as ActivityMonitor.Info) as Void {
        var settings = System.getDeviceSettings();
        var tempStr = "--°";
        var windStr = "--";
        var weatherKind = :cloud;

        var cond = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
        if (cond != null) {
            weatherKind = getWeatherKind(cond.condition);
            var temp = cond.temperature;
            if (temp != null) {
                if (settings.temperatureUnits == System.UNIT_STATUTE) {
                    temp = temp * 1.8 + 32;
                }
                tempStr = Math.round(temp).toNumber().toString() + "°";
            }
            // Wind speed as a bare number, in km/h or mph to match the watch's units
            var speed = cond.windSpeed;
            if (speed != null) {
                windStr = Math.round(speed * (settings.distanceUnits == System.UNIT_STATUTE ? 2.237 : 3.6)).toNumber().toString();
            }
        }
        var hrStr = getHeartRateString();
        var calStr = formatCalories(Config.DEMO ? Demo.CALORIES : activity.calories);

        // Each item is an icon of a fixed width followed by its text
        var font = rowFont();
        var kinds = [:weather, :wind, :heart, :bolt];
        var iconWs = [37, 31, 37, 21];
        var texts = [tempStr, windStr, hrStr, calStr];
        var itemGap = 13;

        var total = itemGap * (kinds.size() - 1);
        for (var i = 0; i < kinds.size(); i++) {
            total += iconWs[i] + dc.getTextWidthInPixels(texts[i], font);
        }

        var x = cx - total / 2;
        for (var i = 0; i < kinds.size(); i++) {
            var kind = kinds[i];
            if (kind == :weather) {
                drawWeatherIcon(dc, x + 15, y + 3, ICON_H / 2, weatherKind);
            } else if (kind == :wind) {
                drawGradientIcon(dc, :wind, x, y, ICON_H / 2 + 1);
            } else if (kind == :heart) {
                drawGradientIcon(dc, :heart, x + 15, y, ICON_H / 2 + 1);
            } else {
                drawGradientIcon(dc, :bolt, x + 8, y, ICON_H / 2 + 1);
            }
            x += iconWs[i];
            dc.setColor(_pale, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, font, texts[i], Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(texts[i], font) + itemGap;
        }
    }

    // Three gusts, the outer two curling at the end; 30px tall at scale 1
    private function drawWindIcon(dc as Dc, x as Numeric, y as Numeric, k as Float) as Void {
        dc.setPenWidth(3);
        dc.drawLine(x, y - 7 * k, x + 16 * k, y - 7 * k);
        dc.drawArc(x + 16 * k, y - 11 * k, 4 * k, Graphics.ARC_COUNTER_CLOCKWISE, 270, 180);
        dc.drawLine(x + 3 * k, y, x + 22 * k, y);
        dc.drawLine(x, y + 7 * k, x + 12 * k, y + 7 * k);
        dc.drawArc(x + 12 * k, y + 11 * k, 4 * k, Graphics.ARC_CLOCKWISE, 90, 180);
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
        // Drawn in the clock gradient's two colours: pale for sun and precipitation, accent for cloud
        if (kind == :sun) {
            drawSun(dc, x, y, r);
        } else if (kind == :partly) {
            drawSun(dc, x + r / 3, y - r / 3, r * 3 / 4);
            drawCloud(dc, x - r / 6, y + r / 4, r * 3 / 4, _accent);
        } else if (kind == :cloud) {
            drawCloud(dc, x, y, r, _accent);
        } else {
            // Rain, snow and storms: a cloud with something falling from it
            drawCloud(dc, x, y - r / 3, r, _accent);
            var top = y + r / 3;
            dc.setColor(_pale, Graphics.COLOR_TRANSPARENT);
            if (kind == :rain) {
                dc.setPenWidth(3);
                for (var i = -1; i <= 1; i++) {
                    var dx = x + i * r / 2;
                    dc.drawLine(dx + 3, top, dx - 2, top + r / 2);
                }
                dc.setPenWidth(1);
            } else if (kind == :snow) {
                for (var i = -1; i <= 1; i++) {
                    dc.fillCircle(x + i * r / 2, top + r / 4 + (i == 0 ? r / 4 : 0), 3);
                }
            } else {
                dc.fillPolygon([[x + 2, top - 2], [x - 6, top + r / 3], [x, top + r / 3],
                                [x - 4, top + r * 2 / 3], [x + 7, top + r / 4], [x + 1, top + r / 4]]);
            }
        }
    }

    private function drawSun(dc as Dc, x as Numeric, y as Numeric, r as Number) as Void {
        dc.setColor(_pale, Graphics.COLOR_TRANSPARENT);
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
        var options = {:period => new Time.Duration(HR_BARS * BAR_SECONDS)};
        if (SensorHistory has :getHeartRateHistory) {
            _hrBars = fillSingleGaps(bucketHistory(SensorHistory.getHeartRateHistory(options), HR_BARS));
        }
        if (SensorHistory has :getStressHistory) {
            // Stress is sampled about every 3 minutes, so every other bar is filled in
            _stressBars = fillSingleGaps(bucketHistory(SensorHistory.getStressHistory(options), STRESS_BARS));
        }
    }

    // Averages samples into `count` bar slots ending now, oldest first. Empty slots are null.
    private function bucketHistory(iter as SensorHistory.SensorHistoryIterator, count as Number) as Array<Number?> {
        var span = count * BAR_SECONDS;
        var start = Time.now().value() - span;
        var sums = new Array<Number>[count];
        var counts = new Array<Number>[count];
        for (var i = 0; i < count; i++) {
            sums[i] = 0;
            counts[i] = 0;
        }

        var sample = iter.next();
        while (sample != null) {
            var value = sample.data;
            var when = sample.when;
            if (value != null && when != null) {
                var slot = (when.value() - start) * count / span;
                if (slot >= 0 && slot < count) {
                    sums[slot] += value.toNumber();
                    counts[slot] += 1;
                }
            }
            sample = iter.next();
        }

        var bars = new Array<Number?>[count];
        for (var j = 0; j < count; j++) {
            bars[j] = counts[j] > 0 ? sums[j] / counts[j] : null;
        }
        return bars;
    }

    // Fills a single missing slot with the slot before it, so occasional missed
    // samples don't leave holes. Longer gaps (watch off the wrist) stay visible.
    private function fillSingleGaps(bars as Array<Number?>) as Array<Number?> {
        for (var i = 1; i < bars.size() - 1; i++) {
            if (bars[i] == null && bars[i - 1] != null && bars[i + 1] != null) {
                bars[i] = bars[i - 1];
            }
        }
        return bars;
    }

    private function drawGraph(dc as Dc, x as Numeric, y as Number, gw as Numeric, gh as Number,
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

        var barW = gw.toFloat() / bars.size();
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

    // Reads the heart rate and stress colour ranges from settings. Heart rate can come from
    // the user's Garmin heart rate zones instead: green at the top of zone 1, red at the
    // top of zone 4, purple in zone 5. Ranges that don't make sense fall back to defaults.
    private function loadRanges() as Void {
        _hrLow = getColorSetting("HrLow", 60);
        _hrHigh = getColorSetting("HrHigh", 120);
        if (getColorSetting("HrRangeSource", 0) == 1 && Toybox has :UserProfile) {
            var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            if (zones != null && zones.size() >= 5) {
                _hrLow = zones[1];
                _hrHigh = zones[4];
            }
        }
        if (_hrLow >= _hrHigh) {
            _hrLow = 60;
            _hrHigh = 120;
        }

        _stressRest = getColorSetting("StressRest", 25);
        _stressLow = getColorSetting("StressLow", 50);
        _stressMedium = getColorSetting("StressMedium", 75);
        if (!(_stressRest < _stressLow && _stressLow < _stressMedium)) {
            _stressRest = 25;
            _stressLow = 50;
            _stressMedium = 75;
        }
    }

    // Coloured zones use bands like Garmin's (rest / low / medium / high). In gradient mode
    // it is pale at the rest level and below, shading to the full end colour at medium.
    private function getStressColor(v as Number) as Number {
        if (_stressGradient) {
            return blendColor(_pale, _accent, clamp01((v - _stressRest).toFloat() / (_stressMedium - _stressRest)));
        }
        if (v <= _stressRest) {
            return 0x3399FF;
        } else if (v <= _stressLow) {
            return 0xFFB366;
        } else if (v <= _stressMedium) {
            return 0xFF8000;
        }
        return 0xFF4D00;
    }

    // Green at or below the low value, through yellow halfway, to red at the high value;
    // purple above it. In gradient mode, start colour at low through to end colour at high.
    private function getHeartRateColor(v as Number) as Number {
        var t = (v - _hrLow).toFloat() / (_hrHigh - _hrLow);
        if (_hrGradient) {
            return blendColor(_pale, _accent, clamp01(t));
        }
        if (v > _hrHigh) {
            return 0xAA33FF;
        }
        if (t <= 0) {
            return 0x00CC44;
        }
        if (t <= 0.5) {
            return blendColor(0x00CC44, 0xFFCC00, t * 2);
        }
        return blendColor(0xFFCC00, 0xFF2200, (t - 0.5) * 2);
    }

    private function clamp01(t as Float) as Float {
        return t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
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

    // ---------------------------------------------------------------- Colour modes

    // Matching [start, end] gradient pairs used by the random mode
    private const RANDOM_PAIRS = [
        [0xCCEEFF, 0x00AAFF], // sky
        [0xE6D9FF, 0x9944FF], // violet
        [0xFFD6E8, 0xFF3399], // pink
        [0xD6FFE0, 0x00CC44], // green
        [0xFFF4C2, 0xFF7700], // sunset
        [0xFFE0CC, 0xFF2244], // ember
        [0xCCEEFF, 0x00CCB3], // teal
        [0xFFFFFF, 0x0055FF]  // deep blue
    ];

    // Sets _pale and _accent from the colour mode setting:
    // 0 = the chosen start/end colours, 1 = a random pair each hour,
    // 2 = following the time of day, season and weather
    private function applyColorMode(clock as System.ClockTime) as Void {
        var mode = getColorSetting("ColorMode", 0);
        var pair = null;
        if (mode == 1) {
            pair = getRandomPair(clock);
        } else if (mode == 2) {
            pair = getContextPair(clock);
        }
        if (pair != null) {
            _pale = pair[0] as Number;
            _accent = pair[1] as Number;
        } else {
            _pale = getColorSetting("StartColor", 0xCCEEFF);
            _accent = getColorSetting("EndColor", 0x00AAFF);
        }
    }

    // Same pair for the whole hour, so it doesn't flicker between redraws
    private function getRandomPair(clock as System.ClockTime) as Array {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        Math.srand(((info.year * 13 + (info.month as Number)) * 32 + info.day) * 24 + clock.hour);
        return RANDOM_PAIRS[Math.rand() % RANDOM_PAIRS.size()] as Array;
    }

    private function getContextPair(clock as System.ClockTime) as Array {
        var hour = clock.hour;
        if (hour >= 21 || hour < 5) {
            return [0xE6D9FF, 0x0055FF]; // night
        }

        var cond = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
        var kind = cond != null ? getWeatherKind(cond.condition) : :cloud;
        if (kind == :storm) {
            return [0xE6D9FF, 0x9944FF];
        } else if (kind == :rain) {
            return [0xCCEEFF, 0x0055FF];
        } else if (kind == :snow) {
            return [0xFFFFFF, 0x00AAFF];
        }

        if (hour < 8) {
            return [0xFFE0CC, 0xFF7700]; // dawn
        } else if (hour >= 18) {
            return [0xFFD6E8, 0xFF3399]; // evening
        } else if (kind == :cloud) {
            return [0xCCEEFF, 0x00AAFF];
        }

        // A sunny or partly cloudy day follows the season. Seasons are flipped
        // south of the equator, using the weather report's location.
        var month = Gregorian.info(Time.now(), Time.FORMAT_SHORT).month as Number;
        if (cond != null) {
            var loc = cond.observationLocationPosition;
            if (loc != null && loc.toDegrees()[0] < 0) {
                month = (month + 5) % 12 + 1;
            }
        }
        if (month >= 3 && month <= 5) {
            return [0xD6FFE0, 0x00CC44]; // spring
        } else if (month >= 6 && month <= 8) {
            return [0xFFF4C2, 0xFF7700]; // summer
        } else if (month >= 9 && month <= 11) {
            return [0xFFE0CC, 0xFF2244]; // autumn
        }
        return [0xFFFFFF, 0x00AAFF]; // winter
    }

    private function getColorSetting(key as String, fallback as Number) as Number {
        var color = Application.Properties.getValue(key);
        return color instanceof Number ? color : fallback;
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
