import DiaconnKit
import LoopKitUI

class DiaconnKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = DiaconnLogger(category: "DiaconnKitPlugin")

    var pumpManagerType: PumpManagerUI.Type? {
        DiaconnPumpManager.self
    }

    override init() {
        super.init()
        log.info("DiaconnKitPlugin loaded")
    }
}
