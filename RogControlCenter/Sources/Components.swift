import SwiftUI

// MARK: - 斜切矩形（ROG 风格分隔）
struct SlantRect: Shape {
    var slant: CGFloat = 4
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 角标切角矩形
struct CutCornerRect: Shape {
    var cut: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        p.closeSubpath()
        return p
    }
}

// MARK: - 圆环仪表
struct RingView: View {
    var value: Double        // 0...1
    var color: Color
    var text: String
    var sub: String
    var title: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0.001, value))))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.55), radius: 4)
                    .animation(.easeInOut(duration: 0.6), value: value)
                VStack(spacing: 1) {
                    Text(text)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 112, height: 112)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - 折线迷你图
struct Sparkline: View {
    var data: [Double]
    var color: Color
    var range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let span = max(0.001, range.upperBound - range.lowerBound)
            let n = max(1, data.count - 1)
            Path { p in
                var started = false
                for (i, v) in data.enumerated() {
                    let x = CGFloat(i) / CGFloat(n) * w
                    let t = min(1, max(0, (v - range.lowerBound) / span))
                    let y = h - CGFloat(t) * (h - 4) - 2
                    if started { p.addLine(to: CGPoint(x: x, y: y)) }
                    else { p.move(to: CGPoint(x: x, y: y)); started = true }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            .shadow(color: color.opacity(0.5), radius: 3)
        }
    }
}

// MARK: - 卡片容器
struct PanelCard<Content: View>: View {
    var title: String
    var meta: String = ""
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    CutCornerRect(cut: 3)
                        .fill(AppTheme.rogRed)
                        .frame(width: 4, height: 13)
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
            }
            content
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.panelGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

// MARK: - 主题
enum AppTheme {
    static let rogRed = Color(red: 1.0, green: 0.176, blue: 0.176)
    static let blue = Color(red: 0.30, green: 0.64, blue: 1.0)
    static let cyan = Color(red: 0.25, green: 0.88, blue: 0.88)
    static let orange = Color(red: 1.0, green: 0.67, blue: 0.25)
    static let green = Color(red: 0.24, green: 0.86, blue: 0.52)
    static let panelGradient = LinearGradient(
        colors: [Color(red: 0.086, green: 0.086, blue: 0.11),
                 Color(red: 0.055, green: 0.055, blue: 0.07)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let bg = Color(red: 0.031, green: 0.031, blue: 0.04)
}
