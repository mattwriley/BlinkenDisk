import AppKit

/// Draws a round LED indicator into an NSImage suitable for an NSStatusItem.
enum LEDRenderer {

    enum LEDColor: String, CaseIterable {
        // Finder label colors - .systemColors respect light/dark mode 
        case red
        case orange
        case yellow
        case green
        case blue
        case purple
        case gray

        var displayName: String {
            switch self {
            case .red: return "Red"
            case .orange: return "Orange"
            case .yellow: return "Yellow"
            case .green: return "Green"
            case .blue: return "Blue"
            case .purple: return "Purple"
            case .gray: return "Gray"
            }
        }

        var onColors: [NSColor] {
            switch self {
            case .red:
                return [.systemRed]
            case .orange:
                return [.systemOrange]
            case .yellow:
                return [.systemYellow]
            case .green:
                return [.systemGreen]
            case .blue:
                return [.systemBlue]
            case .purple:
                return [.systemPurple]
            case .gray:
                return [.systemGray]
            }
        }

        var offColors: [NSColor] {
            let colors = onColors
            return colors.map { color in
                let blended = color.blended(withFraction: 1.0, of: .black) ?? color
                return blended.withAlphaComponent(0.0)
            }
        }
    }

    static func image(
        on: Bool,
        color: LEDColor = .red,
        size: NSSize = NSSize(width: 14, height: 14)
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

        // The bulb body — solid fill
        let fillColor: NSColor
        if on {
            fillColor = color.onColors.first!
        } else {
            fillColor = color.offColors.first!
        }

        ctx.saveGState()
        ctx.addEllipse(in: bulb)
        ctx.clip()
        ctx.setFillColor(fillColor.cgColor)
        ctx.fillEllipse(in: bulb)
        ctx.restoreGState()
        
        // persistent outline for blinking fill
        ctx.saveGState()
        ctx.setStrokeColor(color.onColors.first!.cgColor)
        ctx.setLineWidth(1.25)
        ctx.strokeEllipse(in: bulb)
        ctx.restoreGState()
        
    }
}
