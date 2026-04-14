# DiaconnKit

A Swift framework for integrating the **Diaconn G8** insulin pump with [Trio](https://github.com/nightscout/Trio) via Bluetooth Low Energy.

## Modules

| Module | Description |
|--------|-------------|
| **DiaconnKit** | Core library — BLE communication, packet protocol, pump manager |
| **DiaconnKitUI** | SwiftUI interface — onboarding wizard, settings, device scanning |
| **DiaconnKitPlugin** | LoopKit plugin wrapper for Trio integration |

## Features

- BLE communication via Nordic UART Service (NUS)
- Bolus delivery
- Basal profile management and temp basal
- Real-time pump status and battery monitoring
- Pump event log retrieval and history tracking
- Pump time synchronization

## Dependencies

- [LoopKit](https://github.com/LoopKit/LoopKit) — Pump manager protocols
- CoreBluetooth, HealthKit, SwiftUI, Combine

No third-party dependencies.

## Localization

English, Korean

## License

[MIT](LICENSE)
