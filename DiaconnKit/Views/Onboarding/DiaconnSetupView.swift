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

            Text("Diaconn G8 인슐린 펌프를 Trio에 연결합니다.\n\n펌프가 가까이 있고 블루투스가 켜져 있는지 확인해 주세요.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: nextAction) {
                Text("다음")
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
        .navigationTitle("펌프 설정")
    }
}
