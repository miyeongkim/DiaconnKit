import SwiftUI

struct DiaconnSetupView: View {
    var nextAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("diacong8", bundle: Bundle(for: DiaconnSettingsViewModel.self))
                .resizable()
                .scaledToFit()
                .frame(height: 180)

            Text("Diaconn G8")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Connect the Diaconn G8 insulin pump to Trio.\n\nMake sure the pump is nearby and Bluetooth is turned on.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: nextAction) {
                Text("Next")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .navigationTitle("Pump Setup")
    }
}
