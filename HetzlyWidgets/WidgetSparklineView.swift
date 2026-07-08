import SwiftUI

/// Tiny line-only CPU sparkline for the "Top servers" widget: no axes, no
/// fill, values normalized to the view's bounding rect. Drawn with `Canvas`
/// (the widget target has no access to `Hetzly/Features/Dashboard`'s
/// `SparklineShape`, which lives in the app module).
struct WidgetSparklineView: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }

            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 0
            let range = maxValue - minValue
            let stepX = size.width / CGFloat(values.count - 1)

            var path = Path()
            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * stepX
                let normalized = range > 0 ? (value - minValue) / range : 0.5
                let y = size.height - (CGFloat(normalized) * size.height)
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(WidgetColors.textTertiary), lineWidth: 1.5)
        }
        .frame(width: 40, height: 16)
    }
}

#Preview {
    WidgetSparklineView(values: [12, 18, 15, 40, 55, 30, 22, 60, 45, 20])
        .padding()
        .background(WidgetColors.canvas)
        .preferredColorScheme(.dark)
}
