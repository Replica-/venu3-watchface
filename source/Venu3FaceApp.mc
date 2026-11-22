import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class Venu3FaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new Venu3FaceView()];
    }

    // Called when the user changes settings in Garmin Connect / Express
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
