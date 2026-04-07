import DiaconnKit
import SwiftUI

struct DiaconnScanView: View {
    @ObservedObject var viewModel: DiaconnScanViewModel

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isScanning {
                ProgressView("Diaconn G8을 검색 중...")
                    .padding()
            }

            List(viewModel.devices, id: \.bleIdentifier) { device in
                Button(action: {
                    viewModel.connect(to: device)
                }) {
                    HStack {
                        Image(systemName: "wave.3.right")
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.headline)
                            Text(device.bleIdentifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if viewModel.isConnecting {
                ProgressView("연결 중...")
                    .padding()
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .navigationTitle("펌프 검색")
        .onAppear {
            viewModel.startScanning()
        }
        .onDisappear {
            viewModel.stopScanning()
        }
    }
}
