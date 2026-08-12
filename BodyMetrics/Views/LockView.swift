import SwiftUI

/// 锁定页(生物识别锁启用后,进入后台即覆盖全屏)
struct LockView: View {
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color("PageBackground").ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color("BrandGreen"))
                Text("体重管理")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color("TextPrimary"))
                Text("已锁定")
                    .font(.system(size: 13))
                    .foregroundStyle(Color("TextSecondary"))
                Button {
                    onUnlock()
                } label: {
                    Text("解锁")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 44)
                        .frame(height: 44)
                        .background(Color("BrandGreen"), in: RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)
            }
        }
    }
}

#Preview {
    LockView(onUnlock: {})
}
