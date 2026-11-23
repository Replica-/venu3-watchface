import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class Venu3FaceApp extends Application.AppBase {

    private var _view as Venu3FaceView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Settings saved by an older version keep their old values, so when the defaults
        // change, existing installs are switched to the new ones once. After that the
        // user's own choices are kept.
        var version = Application.Storage.getValue("defaultsVersion");
        if (!(version instanceof Number) || version < 1) {
            // Coloured stress zones, more sensitive stress bands, heart rate green to 60
            // and red at 120
            Application.Properties.setValue("StressGraphStyle", 0);
            Application.Properties.setValue("StressRest", 25);
            Application.Properties.setValue("StressLow", 40);
            Application.Properties.setValue("StressMedium", 60);
            Application.Properties.setValue("HrRangeSource", 0);
            Application.Properties.setValue("HrLow", 60);
            Application.Properties.setValue("HrHigh", 120);
            Application.Storage.setValue("defaultsVersion", 1);
        }
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _view = new Venu3FaceView();
        return [_view as Venu3FaceView];
    }

    // On-watch settings: long-press the watch face, then Customize
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new SettingsMenu(), new SettingsMenuDelegate()];
    }

    // Called when the user changes settings in Garmin Connect / Express, or on the watch
    function onSettingsChanged() as Void {
        if (_view != null) {
            (_view as Venu3FaceView).invalidate();
        }
        WatchUi.requestUpdate();
    }
}
