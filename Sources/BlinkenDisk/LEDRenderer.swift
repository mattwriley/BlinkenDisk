import AppKit

/// Draws a round LED indicator into an NSImage suitable for an NSStatusItem.
/// "On" is bright and glowing with a small specular highlight; "off" is a dim
/// tinted dome so the user can always see where the indicator is.
enum LEDRenderer {

    enum LEDColor: String, CaseIterable {
        case red
        case green
        case yellow
        case amber
        case blue

        var displayName: String {
            switch self {
            case .red: return "Red"
            case .green: return "Green"
            case .yellow: return "Yellow"
            case .amber: return "Amber"
            case .blue: return "Blue"
            }
        }

        var onColors: [NSColor] {
            switch self {
            case .red:
                return [
                    NSColor(red: 1.00, green: 0.92, blue: 0.88, alpha: 1.0),
                    NSColor(red: 1.00, green: 0.18, blue: 0.10, alpha: 1.0),
                    NSColor(red: 0.45, green: 0.00, blue: 0.00, alpha: 1.0),
                ]
            case .green:
                return [
                    NSColor(red: 0.88, green: 1.00, blue: 0.88, alpha: 1.0),
                    NSColor(red: 0.12, green: 0.95, blue: 0.25, alpha: 1.0),
                    NSColor(red: 0.00, green: 0.34, blue: 0.08, alpha: 1.0),
                ]
            case .yellow:
                return [
                    NSColor(red: 1.00, green: 1.00, blue: 0.82, alpha: 1.0),
                    NSColor(red: 1.00, green: 0.88, blue: 0.08, alpha: 1.0),
                    NSColor(red: 0.48, green: 0.34, blue: 0.00, alpha: 1.0),
                ]
            case .amber:
                return [
                    NSColor(red: 1.00, green: 0.94, blue: 0.78, alpha: 1.0),
                    NSColor(red: 1.00, green: 0.52, blue: 0.05, alpha: 1.0),
                    NSColor(red: 0.48, green: 0.17, blue: 0.00, alpha: 1.0),
                ]
            case .blue:
                return [
                    NSColor(red: 0.86, green: 0.94, blue: 1.00, alpha: 1.0),
                    NSColor(red: 0.10, green: 0.50, blue: 1.00, alpha: 1.0),
                    NSColor(red: 0.00, green: 0.10, blue: 0.45, alpha: 1.0),
                ]
            }
        }

        var offColors: [NSColor] {
            let colors = onColors
            return colors.map { color in
                let blended = color.blended(withFraction: 0.70, of: .black) ?? color
                return blended.withAlphaComponent(1.0)
            }
        }
    }

    static func image(
        on: Bool,
        color: LEDColor = .red,
        size: NSSize = NSSize(width: 18, height: 18)
    ) -> NSImage {
        return NSImage(size: size, flipped: false) { rect in
            draw(rect: rect, on: on, color: color)
            return true
        }
    }

    private static func draw(rect: NSRect, on: Bool, color: LEDColor) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Slightly inset so the LED doesn't touch the menu-bar edges.
        let bulb = rect.insetBy(dx: 2, dy: 2)
        let cs = CGColorSpaceCreateDeviceRGB()

        // 1. Dark bezel / shadow under the bulb.
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fillEllipse(in: bulb.insetBy(dx: -0.5, dy: -0.5))
        ctx.restoreGState()

        // 2. The bulb body — radial gradient, brighter near the upper-left.
        let highlightCenter = CGPoint(
            x: bulb.midX - bulb.width * 0.18,
            y: bulb.midY + bulb.height * 0.18
        )
        let bulbCenter = CGPoint(x: bulb.midX, y: bulb.midY)
        let bulbRadius = bulb.width / 2

        let bodyColors: [CGColor]
        let bodyStops: [CGFloat] = [0.0, 0.45, 1.0]
        if on {
            bodyColors = color.onColors.map(\.cgColor)
        } else {
            bodyColors = color.offColors.map(\.cgColor)
        }
        guard let bodyGradient = CGGradient(colorsSpace: cs, colors: bodyColors as CFArray, locations: bodyStops) else {
            return
        }

        ctx.saveGState()
        ctx.addEllipse(in: bulb)
        ctx.clip()
        ctx.drawRadialGradient(
            bodyGradient,
            startCenter: highlightCenter, startRadius: 0,
            endCenter: bulbCenter, endRadius: bulbRadius,
            options: [.drawsAfterEndLocation]
        )
        ctx.restoreGState()

        // 3. Specular highlight — small bright crescent on the upper-left.
        ctx.saveGState()
        ctx.addEllipse(in: bulb)
        ctx.clip()
        let highlightRect = NSRect(
            x: bulb.minX + bulb.width * 0.18,
            y: bulb.midY + bulb.height * 0.05,
            width: bulb.width * 0.40,
            height: bulb.height * 0.30
        )
        let highlightAlpha: CGFloat = on ? 0.85 : 0.18
        let highlightColors: [CGColor] = [
            NSColor.white.withAlphaComponent(highlightAlpha).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor,
        ]
        if let hg = CGGradient(colorsSpace: cs, colors: highlightColors as CFArray, locations: [0.0, 1.0]) {
            ctx.drawRadialGradient(
                hg,
                startCenter: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                startRadius: 0,
                endCenter: CGPoint(x: highlightRect.midX, y: highlightRect.midY),
                endRadius: max(highlightRect.width, highlightRect.height) / 2,
                options: []
            )
        }
        ctx.restoreGState()

        // 4. Thin rim around the bulb for definition.
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(on ? 0.45 : 0.55).cgColor)
        ctx.setLineWidth(0.5)
        ctx.strokeEllipse(in: bulb)
        ctx.restoreGState()
    }
}
