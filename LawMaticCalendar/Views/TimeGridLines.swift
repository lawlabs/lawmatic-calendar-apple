import SwiftUI

/// Линии сетки времени (горизонтальные — по часам, вертикальные — между
/// колонками дней), нарисованные одним `Canvas` вместо сотен `Rectangle`.
struct TimeGridLines: View {
    let hourHeight: CGFloat
    let hourCount: Int
    let columnCount: Int

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var path = Path()

            for hour in 0 ..< hourCount {
                let y = (CGFloat(hour) * hourHeight).rounded() + 0.5
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            if columnCount > 1 {
                let columnWidth = size.width / CGFloat(columnCount)
                for column in 1 ..< columnCount {
                    let x = (CGFloat(column) * columnWidth).rounded() - 0.5
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }

            context.stroke(path, with: .color(Color.calendarSeparator), lineWidth: 1)
        }
        .frame(height: CGFloat(hourCount) * hourHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
