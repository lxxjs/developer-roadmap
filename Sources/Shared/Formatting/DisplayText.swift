import Foundation

/// Text budgets for the watch screen.
///
/// The watch is the constraint here, and character counts are the wrong unit
/// for it: a Hangul syllable occupies about twice the width of a Latin letter,
/// so "우회전 후 직진" and "turn right then go" are nowhere near the same size on
/// screen despite similar lengths. Everything below measures *display width*,
/// counting wide scalars as two cells.
///
/// The budgets target the smallest watch watchOS 10 runs on — the 40 mm Series
/// 4/5/6 at 162 points wide, leaving roughly 150 points of content. At the
/// caption sizes the compass screen uses that is about 22 cells; 20 is used to
/// keep a margin for the wider system fonts and accessibility sizes.
enum DisplayText {
    /// Cells available to a single caption line on the narrowest supported watch.
    static let captionBudget = 20
    /// Cells the destination name in the compass header may occupy.
    static let headerBudget = 18

    /// Display width in cells, counting full-width scalars as two.
    static func displayWidth(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + (isWide($1) ? 2 : 1) }
    }

    /// Trims `text` to `limit` cells, preferring a word boundary and marking
    /// the cut with an ellipsis.
    ///
    /// Breaking on a space matters more than squeezing in a few more cells: a
    /// glance at a wrist reads whole words, and a fragment of one is noise.
    static func truncate(_ text: String, toDisplayWidth limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 1, displayWidth(trimmed) > limit else { return trimmed }

        // One cell is reserved for the ellipsis.
        let budget = limit - 1
        var kept = ""
        var width = 0
        var lastBoundary: String?

        for character in trimmed {
            let characterWidth = displayWidth(String(character))
            if width + characterWidth > budget { break }
            if character == " " { lastBoundary = kept }
            kept.append(character)
            width += characterWidth
        }

        // Fall back to the hard cut when breaking on a space would throw away
        // more than a third of what fits.
        let candidate: String
        if let boundary = lastBoundary, displayWidth(boundary) * 3 >= budget * 2 {
            candidate = boundary
        } else {
            candidate = kept
        }
        let result = candidate.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "…" : result + "…"
    }

    /// A routing instruction, shortened for the compass screen.
    ///
    /// MapKit's Korean walking instructions run long — "○○로 방면으로 우회전한
    /// 다음 100미터 직진" and similar — and the screen has one caption line for
    /// them. Returns `nil` for an instruction with nothing in it, so the caller
    /// can show the turn distance instead, which is the more useful of the two
    /// while walking.
    static func compactInstruction(_ instruction: String?, limit: Int = captionBudget) -> String? {
        guard let instruction else { return nil }
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return truncate(trimmed, toDisplayWidth: limit)
    }

    /// A destination name for the compass header.
    static func compactPlaceName(_ name: String, limit: Int = headerBudget) -> String {
        truncate(name, toDisplayWidth: limit)
    }

    /// Scalars that render about twice as wide as a Latin letter.
    ///
    /// Covers what this app actually shows: Hangul, CJK ideographs, the
    /// full-width forms, and CJK punctuation.
    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x115F,   // Hangul Jamo initial consonants
             0x2E80...0x303E,   // CJK radicals and punctuation
             0x3041...0x33FF,   // Hiragana, Katakana, CJK compatibility
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified ideographs
             0xA000...0xA4CF,   // Yi
             0xAC00...0xD7A3,   // Hangul syllables
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFE30...0xFE4F,   // CJK compatibility forms
             0xFF00...0xFF60,   // Full-width forms
             0xFFE0...0xFFE6,
             0x1F300...0x1F9FF: // Emoji
            return true
        default:
            return false
        }
    }
}
