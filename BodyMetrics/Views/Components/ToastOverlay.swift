import SwiftUI

/// 一条 toast。带撤销的会多停留几秒,够看清再决定
struct ToastMessage: Equatable {
    let id = UUID()
    var text: String
    var undo: (() -> Void)?

    var duration: TimeInterval { undo == nil ? 2.2 : 6 }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

/// 底部 toast。
///
/// 删除一律配撤销而不是二次确认弹窗:确认弹窗打断操作流,撤销既不打断又真能救回来。
struct ToastOverlay: ViewModifier {
    @Binding var message: ToastMessage?
    /// 距底部的距离(记录页有底部按钮,要抬高一点)
    var bottomPadding: CGFloat = 30

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    HStack(spacing: 12) {
                        Text(message.text)
                            .font(.system(size: 13))
                            .foregroundStyle(Color("PageBackground"))
                        if let undo = message.undo {
                            Button(String(localized: "撤销")) {
                                undo()
                                self.message = nil
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color("BrandGreen"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Color("TextPrimary"), in: RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal, 18)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: message)
            .onChange(of: message) { _, newValue in
                dismissTask?.cancel()
                guard let newValue else { return }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(newValue.duration))
                    guard !Task.isCancelled else { return }
                    if message?.id == newValue.id { message = nil }
                }
            }
    }
}

extension View {
    func toast(_ message: Binding<ToastMessage?>, bottomPadding: CGFloat = 30) -> some View {
        modifier(ToastOverlay(message: message, bottomPadding: bottomPadding))
    }
}
