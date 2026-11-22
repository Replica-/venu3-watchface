import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class Venu3FaceApp extends Application.AppBase {

    private var _view as Venu3FaceView?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _view = new Venu3FaceView();
        return [_view as Venu3FaceView];
    }

    // Called when the user changes settings in Garmin Connect / Express
    function onSettingsChanged() as Void {
        if (_view != null) {
            (_view as Venu3FaceView).invalidate();
        }
        WatchUi.requestUpdate();
    }
}
