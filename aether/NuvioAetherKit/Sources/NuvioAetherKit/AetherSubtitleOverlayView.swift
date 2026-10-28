import UIKit
internal import AetherEngine

/// Nuvio's subtitle look, in the units the MPV player receives it in: colors as `#AARRGGBB`, sizes
/// in mpv "scaled pixels" (relative to a 720 px tall window), `subPos` as mpv's `sub-pos`
/// (100 = bottom, lower values move the subtitles up).
public struct NuvioAetherSubtitleStyle: Sendable, Equatable {
    public var textColor = "#FFFFFFFF"
    public var backgroundColor = "#00000000"
    public var outlineColor = "#FF000000"
    public var outlineSize: Float = 3
    public var bold = false
    public var fontSize: Float = 54
    public var subPos = 100
    public var stripSdh = false

    public init() {}
}

/// Draws AetherEngine's subtitle cues over the video. The engine decodes subtitles but leaves the
/// rendering to the host: text cues are laid out with Nuvio's style, bitmap cues (PGS, DVB, VobSub)
/// are placed on the video rectangle they were authored against.
@MainActor
final class AetherSubtitleOverlayView: UIView {
    var style = NuvioAetherSubtitleStyle() {
        didSet { if style != oldValue { rebuild() } }
    }

    /// The rectangle the picture occupies inside this view, for bitmap cues.
    var videoRect: CGRect = .zero {
        didSet { if videoRect != oldValue { setNeedsLayout() } }
    }

    private var cues: [SubtitleCue] = []
    private var textBlocks: [SubtitleTextBlock] = []
    private var imageViews: [UIImageView] = []
    private var builtSize: CGSize = .zero
    private var builtVideoRect: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows exactly `activeCues`; a no-op when they did not change.
    func show(_ activeCues: [SubtitleCue]) {
        guard activeCues.map(\.id) != cues.map(\.id) else { return }
        cues = activeCues
        rebuild()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Only geometry changes rebuild here: adding the cue views must not loop back into layout.
        if bounds.size != builtSize || videoRect != builtVideoRect {
            rebuild()
        }
    }

    private func rebuild() {
        builtSize = bounds.size
        builtVideoRect = videoRect
        textBlocks.forEach { $0.removeFromSuperview() }
        textBlocks.removeAll()
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        guard bounds.width > 1, bounds.height > 1, !cues.isEmpty else { return }

        var bands: [Band: [SubtitleCue]] = [:]
        for cue in cues {
            switch cue.body {
            case .image(let image):
                addImage(image)
            case .text, .richText:
                bands[Band(alignment: cue.placement?.alignment), default: []].append(cue)
            }
        }
        for (band, bandCues) in bands {
            addTextBlock(band: band, cues: bandCues.sorted { $0.startTime < $1.startTime })
        }
    }

    // MARK: - Text

    private enum Band: Hashable {
        case top, middle, bottom

        /// ASS numpad alignment: 1-3 bottom, 4-6 middle, 7-9 top.
        init(alignment: Int?) {
            switch alignment ?? 2 {
            case 7...9: self = .top
            case 4...6: self = .middle
            default: self = .bottom
            }
        }
    }

    private var scale: CGFloat { bounds.height / 720 }

    private func addTextBlock(band: Band, cues: [SubtitleCue]) {
        let fontSize = max(12, CGFloat(style.fontSize) * scale)
        let text = NSMutableAttributedString()
        for cue in cues {
            guard let cueText = attributedText(for: cue, fontSize: fontSize), cueText.length > 0 else { continue }
            if text.length > 0 { text.append(NSAttributedString(string: "\n")) }
            text.append(cueText)
        }
        guard text.length > 0 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment(for: cues.first?.placement?.alignment)
        paragraph.lineBreakMode = .byWordWrapping
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))

        let block = SubtitleTextBlock(
            text: text,
            outlineColor: UIColor(nuvioARGB: style.outlineColor) ?? .black,
            outlineWidth: CGFloat(max(0, style.outlineSize)) * scale,
            boxColor: UIColor(nuvioARGB: style.backgroundColor) ?? .clear
        )
        addSubview(block)
        textBlocks.append(block)

        let horizontalMargin = max(16, bounds.width * 0.05)
        let maxWidth = bounds.width - horizontalMargin * 2
        let size = block.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let x: CGFloat
        switch paragraph.alignment {
        case .left: x = horizontalMargin
        case .right: x = bounds.width - horizontalMargin - size.width
        default: x = (bounds.width - size.width) / 2
        }
        let margin = 22 * scale
        let y: CGFloat
        switch band {
        case .top:
            y = margin
        case .middle:
            y = (bounds.height - size.height) / 2
        case .bottom:
            // mpv's sub-pos: the bottom edge sits at subPos% of the height, minus its margin.
            let bottom = bounds.height * CGFloat(style.subPos) / 100 - margin
            y = min(bounds.height - margin, bottom) - size.height
        }
        block.frame = CGRect(x: x, y: max(margin, y), width: size.width, height: size.height)
    }

    private func attributedText(for cue: SubtitleCue, fontSize: CGFloat) -> NSAttributedString? {
        let textColor = UIColor(nuvioARGB: style.textColor) ?? .white
        let result = NSMutableAttributedString()
        switch cue.body {
        case .text(let text):
            let cleaned = cleanup(text)
            guard !cleaned.isEmpty else { return nil }
            result.append(NSAttributedString(string: cleaned, attributes: [
                .font: font(size: fontSize, bold: style.bold, italic: false),
                .foregroundColor: textColor,
            ]))
        case .richText(let runs):
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font(size: fontSize, bold: style.bold || run.isBold, italic: run.isItalic),
                    .foregroundColor: run.color.map {
                        UIColor(red: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1)
                    } ?? textColor,
                ]
                if run.isUnderlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if run.isStruckThrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if style.stripSdh {
                let cleaned = cleanup(result.string)
                guard !cleaned.isEmpty else { return nil }
                if cleaned != result.string.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // Styling cannot survive the SDH strip span by span; keep the text.
                    return NSAttributedString(string: cleaned, attributes: [
                        .font: font(size: fontSize, bold: style.bold, italic: false),
                        .foregroundColor: textColor,
                    ])
                }
            }
        case .image:
            return nil
        }
        return result
    }

    private func cleanup(_ text: String) -> String {
        var value = text
        if style.stripSdh {
            for pattern in ["\\[[^\\]]*\\]", "\\([^)]*\\)", "(?m)^\\s*[A-Z][A-Z0-9 .'-]{1,30}:\\s*", "[♪♫]+"] {
                value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
        }
        return value
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .semibold)
        guard italic, let descriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(.traitItalic)
        ) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    private func textAlignment(for alignment: Int?) -> NSTextAlignment {
        switch alignment ?? 2 {
        case 1, 4, 7: return .left
        case 3, 6, 9: return .right
        default: return .center
        }
    }

    // MARK: - Bitmaps

    private func addImage(_ image: SubtitleImage) {
        let video = videoRect.width > 1 && videoRect.height > 1 ? videoRect : bounds
        // The composition canvas is width-aligned and centred on the picture (AetherEngine #112).
        var canvas = video
        if image.canvasSize.width > 0, image.canvasSize.height > 0 {
            let height = video.width * image.canvasSize.height / image.canvasSize.width
            canvas = CGRect(x: video.minX, y: video.midY - height / 2, width: video.width, height: height)
        }
        let view = UIImageView(image: UIImage(cgImage: image.cgImage))
        view.contentMode = .scaleToFill
        view.frame = CGRect(
            x: canvas.minX + image.position.minX * canvas.width,
            y: canvas.minY + image.position.minY * canvas.height,
            width: image.position.width * canvas.width,
            height: image.position.height * canvas.height
        )
        addSubview(view)
        imageViews.append(view)
    }
}

/// One block of subtitle lines: an optional box behind, the outline, then the fill.
@MainActor
private final class SubtitleTextBlock: UIView {
    private let fillLabel = UILabel()
    private let outlineLabel = UILabel()
    private let padding: UIEdgeInsets

    init(text: NSAttributedString, outlineColor: UIColor, outlineWidth: CGFloat, boxColor: UIColor) {
        let hasBox = boxColor.cgColor.alpha > 0.01
        padding = hasBox ? UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8) : .zero
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = hasBox ? boxColor : .clear
        layer.cornerRadius = hasBox ? 6 : 0

        for label in [outlineLabel, fillLabel] {
            label.numberOfLines = 0
            label.backgroundColor = .clear
            addSubview(label)
        }
        fillLabel.attributedText = text

        if !hasBox, outlineWidth > 0 {
            // A stroke-only copy behind the fill: half the stroke falls outside the glyphs.
            let outlined = NSMutableAttributedString(attributedString: text)
            outlined.enumerateAttribute(.font, in: NSRange(location: 0, length: outlined.length)) { value, range, _ in
                let pointSize = (value as? UIFont)?.pointSize ?? 20
                outlined.addAttributes([
                    .strokeColor: outlineColor,
                    .strokeWidth: outlineWidth * 2 / pointSize * 100,
                ], range: range)
            }
            outlineLabel.attributedText = outlined
        } else {
            outlineLabel.isHidden = true
        }

        if !hasBox {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.55
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: 1)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = CGSize(width: size.width - padding.left - padding.right, height: size.height)
        let fitted = fillLabel.sizeThatFits(inner)
        return CGSize(
            width: ceil(fitted.width) + padding.left + padding.right,
            height: ceil(fitted.height) + padding.top + padding.bottom
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inner = bounds.inset(by: padding)
        fillLabel.frame = inner
        outlineLabel.frame = inner
    }
}

extension UIColor {
    /// Parses mpv's `#AARRGGBB` (and `#RRGGBB`).
    convenience init?(nuvioARGB value: String) {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard let number = UInt32(hex, radix: 16) else { return nil }
        let alpha, red, green, blue: UInt32
        switch hex.count {
        case 8:
            alpha = (number >> 24) & 0xFF
            red = (number >> 16) & 0xFF
            green = (number >> 8) & 0xFF
            blue = number & 0xFF
        case 6:
            alpha = 0xFF
            red = (number >> 16) & 0xFF
            green = (number >> 8) & 0xFF
            blue = number & 0xFF
        default:
            return nil
        }
        self.init(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
