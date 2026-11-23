import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch settings: long-press the watch face, then Customize.
// The same properties as the Garmin Connect settings (resources/settings).

// A list setting: property key, menu title, then its values and their labels
const LIST_SETTINGS = [
    ["ColorMode", Rez.Strings.MenuColorMode, [0, 1, 2],
        [Rez.Strings.ColorModeFixed, Rez.Strings.ColorModeRandom, Rez.Strings.ColorModeContext]],
    ["StartColor", Rez.Strings.MenuStartColor,
        [0xCCEEFF, 0xFFFFFF, 0xFFD6E8, 0xD6FFE0, 0xFFF4C2, 0xE6D9FF, 0xFFE0CC],
        [Rez.Strings.ColorPaleBlue, Rez.Strings.ColorWhite, Rez.Strings.ColorPalePink, Rez.Strings.ColorPaleGreen, Rez.Strings.ColorPaleYellow,
         Rez.Strings.ColorLavender, Rez.Strings.ColorPeach]],
    ["EndColor", Rez.Strings.MenuEndColor,
        [0x00AAFF, 0x0055FF, 0x00CCB3, 0x00CC44, 0xFF7700, 0xFF2244, 0xFF3399, 0x9944FF],
        [Rez.Strings.ColorSkyBlue, Rez.Strings.ColorDeepBlue, Rez.Strings.ColorTeal, Rez.Strings.ColorGreen, Rez.Strings.ColorOrange, Rez.Strings.ColorRed,
         Rez.Strings.ColorPink, Rez.Strings.ColorPurple]],
    ["HrGraphStyle", Rez.Strings.MenuHrGraph, [0, 1], [Rez.Strings.GraphZones, Rez.Strings.GraphGradient]],
    ["StressGraphStyle", Rez.Strings.MenuStressGraph, [0, 1], [Rez.Strings.GraphZones, Rez.Strings.GraphGradient]],
    ["HrRangeSource", Rez.Strings.MenuHrRange, [0, 1], [Rez.Strings.HrRangeCustom, Rez.Strings.HrRangeZones]]
];

// A number setting: key, menu title, default, min, max, step, and the settings it
// must stay above and below (so the colour ranges stay in order)
const NUMBER_SETTINGS = [
    ["HrLow", Rez.Strings.MenuHrLow, 60, 30, 215, 5, null, "HrHigh"],
    ["HrHigh", Rez.Strings.MenuHrHigh, 120, 35, 220, 5, "HrLow", null],
    ["StressRest", Rez.Strings.MenuStressRest, 25, 0, 90, 5, null, "StressLow"],
    ["StressLow", Rez.Strings.MenuStressLow, 40, 5, 95, 5, "StressRest", "StressMedium"],
    ["StressMedium", Rez.Strings.MenuStressMedium, 60, 10, 100, 5, "StressLow", null]
];

function loadString(id as ResourceId) as String {
    return WatchUi.loadResource(id) as String;
}

function readSetting(key as String, fallback as Number) as Number {
    var v = Application.Properties.getValue(key);
    return v instanceof Number ? v : fallback;
}

function numberDefault(key as String) as Number {
    for (var i = 0; i < NUMBER_SETTINGS.size(); i++) {
        var def = NUMBER_SETTINGS[i] as Array;
        if ((def[0] as String).equals(key)) {
            return def[2] as Number;
        }
    }
    return 0;
}

// The text shown under a setting in the main menu: its current value
function listSubLabel(def as Array) as String {
    var values = def[2] as Array;
    var labels = def[3] as Array;
    var current = readSetting(def[0] as String, values[0] as Number);
    for (var i = 0; i < values.size(); i++) {
        if (values[i] == current) {
            return loadString(labels[i] as ResourceId);
        }
    }
    return "";
}

function numberSubLabel(def as Array) as String {
    return readSetting(def[0] as String, def[2] as Number).toString();
}

class SettingsMenu extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => loadString(Rez.Strings.AppName)});
        for (var i = 0; i < LIST_SETTINGS.size(); i++) {
            var def = LIST_SETTINGS[i] as Array;
            addItem(new WatchUi.MenuItem(loadString(def[1] as ResourceId), listSubLabel(def), "L" + i, null));
        }
        for (var i = 0; i < NUMBER_SETTINGS.size(); i++) {
            var def = NUMBER_SETTINGS[i] as Array;
            addItem(new WatchUi.MenuItem(loadString(def[1] as ResourceId), numberSubLabel(def), "N" + i, null));
        }
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as String;
        var index = (id.substring(1, id.length()) as String).toNumber() as Number;
        var isList = id.toCharArray()[0] == 'L';
        var def = (isList ? LIST_SETTINGS[index] : NUMBER_SETTINGS[index]) as Array;
        var key = def[0] as String;

        var menu = new WatchUi.Menu2({:title => loadString(def[1] as ResourceId)});
        var values = [] as Array<Number>;
        var current;
        if (isList) {
            var labels = def[3] as Array;
            values = def[2] as Array<Number>;
            current = readSetting(key, values[0]);
            for (var i = 0; i < values.size(); i++) {
                menu.addItem(new WatchUi.MenuItem(loadString(labels[i] as ResourceId), null, values[i], null));
            }
        } else {
            current = readSetting(key, def[2] as Number);
            var step = def[5] as Number;
            var lo = def[3] as Number;
            var hi = def[4] as Number;
            if (def[6] != null) {
                var other = def[6] as String;
                var min = readSetting(other, numberDefault(other)) + step;
                lo = min > lo ? min : lo;
            }
            if (def[7] != null) {
                var other = def[7] as String;
                var max = readSetting(other, numberDefault(other)) - step;
                hi = max < hi ? max : hi;
            }
            for (var v = lo; v <= hi; v += step) {
                values.add(v);
                menu.addItem(new WatchUi.MenuItem(v.toString(), null, v, null));
            }
        }

        // Start on the current value, or the nearest one
        var focus = 0;
        for (var i = 1; i < values.size(); i++) {
            if ((values[i] - current).abs() < (values[focus] - current).abs()) {
                focus = i;
            }
        }
        menu.setFocus(focus);

        WatchUi.pushView(menu, new SettingsOptionDelegate(key, item, isList ? def : null), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// Saves the picked value and goes back to the main settings menu
class SettingsOptionDelegate extends WatchUi.Menu2InputDelegate {
    private var _key as String;
    private var _parentItem as WatchUi.MenuItem;
    private var _listDef as Array?;

    function initialize(key as String, parentItem as WatchUi.MenuItem, listDef as Array?) {
        Menu2InputDelegate.initialize();
        _key = key;
        _parentItem = parentItem;
        _listDef = listDef;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var value = item.getId() as Number;
        Application.Properties.setValue(_key, value);
        _parentItem.setSubLabel(_listDef != null ? listSubLabel(_listDef) : value.toString());
        (Application.getApp() as Venu3FaceApp).onSettingsChanged();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
