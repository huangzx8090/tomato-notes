import SwiftUI

struct RotaryDial: View {
    let title: String
    let unit: String
    let bounds: ClosedRange<Int>
    let tint: Color
    @Binding var value: Int
    @ViewState private var dragStartValue: Int?
    @ViewState private var previousAngle: Double?
    @ViewState private var accumulatedAngle = 0.0
    @ViewState private var isDragging = false
    private let size: CGFloat = 124

    private var progress: Double { Double(value - bounds.lowerBound) / Double(bounds.upperBound - bounds.lowerBound) }
    private var angle: Double { -135 + progress * 270 }

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
            ZStack {
                Circle().stroke(Theme.border.opacity(0.45), lineWidth: 1).padding(3)
                ForEach(0..<37) { index in
                    Capsule()
                        .fill(Double(index) / 36 <= progress ? tint.opacity(0.75) : Theme.border)
                        .frame(width: index % 3 == 0 ? 2 : 1, height: index % 3 == 0 ? 7 : 4)
                        .offset(y: -size / 2 + 8)
                        .rotationEffect(.degrees(-135 + Double(index) * 7.5))
                }
                Circle()
                    .fill(LinearGradient(colors: [Theme.dialRimLight, Theme.dialRimShadow, Theme.dialRimEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(16)
                    .shadow(color: Theme.dialShadow.opacity(isDragging ? 0.26 : 0.36), radius: isDragging ? 3 : 6, x: 0, y: isDragging ? 2 : 5)
                ForEach(0..<60) { index in
                    Capsule().fill(Color(hex: 0xAFA69A).opacity(index % 2 == 0 ? 0.28 : 0.13))
                        .frame(width: 1, height: 3).offset(y: -size / 2 + 19)
                        .rotationEffect(.degrees(Double(index) * 6))
                }
                Circle()
                    .fill(LinearGradient(colors: [Theme.dialFaceLight, Theme.dialFaceShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(Theme.dialHighlight.opacity(0.95), lineWidth: 1))
                    .padding(23)
                Capsule().fill(tint).frame(width: 3, height: 10).offset(y: -size / 2 + 28)
                    .rotationEffect(.degrees(angle))
                VStack(spacing: 1) {
                    Text("\(value)").font(.system(size: 23, weight: .medium, design: .rounded).monospacedDigit())
                    Text(unit).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.secondary)
                }.foregroundStyle(Theme.primary).offset(y: 3)
            }
            .frame(width: size, height: size).contentShape(Circle())
            .scaleEffect(isDragging ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: isDragging)
            .gesture(drag)
            .focusable()
            .onMoveCommand { direction in
                switch direction {
                case .up, .right: adjust(1)
                case .down, .left: adjust(-1)
                default: break
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title)旋钮")
            .accessibilityValue("\(value)\(unit)")
            .accessibilityAdjustableAction { direction in adjust(direction == .increment ? 1 : -1) }
            .help("拖动旋钮调节；聚焦后可用方向键微调")
            HStack(spacing: 11) {
                adjustmentButton("minus", delta: -1)
                Text("\(bounds.lowerBound)–\(bounds.upperBound)")
                    .font(.system(size: 9).monospacedDigit()).foregroundStyle(Theme.secondary)
                adjustmentButton("plus", delta: 1)
            }
        }.frame(maxWidth: .infinity)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { event in
                let startX = event.startLocation.x - size / 2
                let startY = size / 2 - event.startLocation.y
                if dragStartValue == nil {
                    dragStartValue = value
                    // 统一为 Double，避免不同 Swift 工具链在 CGFloat / Double 之间推断歧义。
                    previousAngle = atan2(Double(startX), Double(startY)) * 180 / Double.pi
                    accumulatedAngle = 0
                }
                isDragging = true
                if hypot(startX, startY) < 22 {
                    // 表盘中心难以确定旋转角度，改用上下拖动，避免数值跳变。
                    set((dragStartValue ?? value) + Int((-event.translation.height / 3).rounded()))
                } else {
                    let current = atan2(Double(event.location.x - size / 2), Double(size / 2 - event.location.y)) * 180 / Double.pi
                    var delta = current - (previousAngle ?? current)
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    accumulatedAngle += delta
                    previousAngle = current
                    set((dragStartValue ?? value) + Int((accumulatedAngle / 270 * Double(bounds.upperBound - bounds.lowerBound)).rounded()))
                }
            }.onEnded { _ in dragStartValue = nil; previousAngle = nil; isDragging = false }
    }

    private func adjustmentButton(_ symbol: String, delta: Int) -> some View {
        Button { adjust(delta) } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .frame(width: 23, height: 23).background(Theme.background, in: Circle())
                .overlay(Circle().stroke(Theme.border.opacity(0.8), lineWidth: 0.6)).contentShape(Circle())
        }.buttonStyle(.plain).foregroundStyle(Theme.secondary)
            .accessibilityLabel("\(title)\(delta > 0 ? "增加" : "减少")1\(unit)")
            .disabled(delta < 0 ? value <= bounds.lowerBound : value >= bounds.upperBound)
    }
    private func adjust(_ delta: Int) { set(value + delta) }
    private func set(_ next: Int) { value = min(bounds.upperBound, max(bounds.lowerBound, next)) }
}
