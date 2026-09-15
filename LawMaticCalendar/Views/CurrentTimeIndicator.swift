import Combine
import SwiftUI

/// Красная линия текущего времени с меткой часов; обновляется раз в минуту.
struct CurrentTimeIndicator: View {
    let hourHeight: CGFloat

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let hour = Calendar.current.component(.hour, from: currentTime)
        let minute = Calendar.current.component(.minute, from: currentTime)
        let offset = CGFloat(hour * 60 + minute) * (hourHeight / 60)

        HStack(spacing: 0) {
            Text(Self.timeFormatter.string(from: currentTime))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.red))
                .offset(x: 8)

            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
                .offset(x: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: offset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}
