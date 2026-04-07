import SwiftUI

struct DiaconnSetupCompleteView: View {
    var finish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.green)

            Text("설정 완료")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Diaconn G8 펌프가 성공적으로 연결되었습니다.\n\nTrio가 자동으로 인슐린 전달을 관리합니다.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button(action: finish) {
                Text("완료")
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
        .navigationTitle("설정 완료")
    }
}
