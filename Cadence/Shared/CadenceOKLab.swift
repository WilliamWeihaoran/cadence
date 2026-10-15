import Foundation

/// OKLab, the one piece of colour arithmetic WCAG relative luminance cannot do.
///
/// ## Why this exists (T-3168)
///
/// `CadenceCalendarEventStyle` solves every fill to a **relative luminance** target, and relative
/// luminance is weighted `0.2126 R / 0.7152 G / 0.0722 B`. A green reaches a given Y with very
/// little chroma; a red needs more, and a blue needs almost all the gamut has. So "solve every
/// plate to Y = 0.030" produces plates that are the same *lightness* and nowhere near the same
/// *colourfulness* — measured on the T-3160 sweep, the rail plate ran from chroma 0.039 for a cyan
/// to **0.234 for a pure blue**, a six-fold spread at one luminance.
///
/// That spread is visible, and it is visible in the direction luminance cannot see. The
/// **Helmholtz–Kohlrausch effect** is the long-documented result that a more saturated sample is
/// judged *brighter* than a less saturated one of the same luminance; the brightness-to-luminance
/// ratio rises with chroma at every luminance level. Neither WCAG 2.x nor APCA models it — both
/// are luminance-only — which is why a `#0000ff` event block could sit four times darker than a
/// task block by measurement and still read as the loudest thing on the canvas.
///
/// Separating lightness from chroma needs a space where they are actually separate axes. HSB is
/// not one: `brightness` at fixed `saturation` moves both. OKLab is, to a good approximation, and
/// its chroma `sqrt(a² + b²)` is the number the eye reads as "how much colour is in this".
///
/// ## Scope
///
/// Deliberately small, and deliberately **not** a `Color` extension. This is plain arithmetic over
/// sRGB components so it stays testable, allocation-free and free of AppKit/UIKit — the calendar
/// style runs it once per chip on a month grid. Nothing here paints anything; `Theme` is still the
/// only source of app-defined colour.
enum CadenceOKLab {

    /// OKLab's three axes for an sRGB colour: perceptual lightness, and the two opponent-colour
    /// axes whose magnitude is chroma.
    ///
    /// The matrices are Björn Ottosson's published sRGB⇄OKLab pair. The cube roots are taken with
    /// the sign carried through, because the LMS intermediates can go slightly negative for
    /// colours near the edge of the gamut and `pow` of a negative base is NaN.
    static func components(
        red: Double,
        green: Double,
        blue: Double
    ) -> (lightness: Double, a: Double, b: Double) {
        let r = linearized(red)
        let g = linearized(green)
        let b = linearized(blue)

        let long = (0.4122214708 * r) + (0.5363325363 * g) + (0.0514459929 * b)
        let medium = (0.2119034982 * r) + (0.6806995451 * g) + (0.1073969566 * b)
        let short = (0.0883024619 * r) + (0.2817188376 * g) + (0.6299787005 * b)

        let l = signedCubeRoot(long)
        let m = signedCubeRoot(medium)
        let s = signedCubeRoot(short)

        return (
            lightness: (0.2104542553 * l) + (0.7936177850 * m) - (0.0040720468 * s),
            a: (1.9779984951 * l) - (2.4285922050 * m) + (0.4505937099 * s),
            b: (0.0259040371 * l) + (0.7827717662 * m) - (0.8086757660 * s)
        )
    }

    /// How much colour an sRGB value carries, independent of how light it is. Zero for every grey,
    /// and about 0.31 for the most saturated thing sRGB can show (a primary blue).
    static func chroma(red: Double, green: Double, blue: Double) -> Double {
        let parts = components(red: red, green: green, blue: blue)
        return (parts.a * parts.a + parts.b * parts.b).squareRoot()
    }

    /// Perceptual lightness of an sRGB value.
    static func lightness(red: Double, green: Double, blue: Double) -> Double {
        components(red: red, green: green, blue: blue).lightness
    }

    /// OKLab lightness of the **grey** whose WCAG relative luminance is `relativeLuminance`.
    ///
    /// This is a closed form rather than a search, and the reason is worth one line: for a neutral,
    /// the linear R, G and B are all equal to Y, so the three LMS intermediates are each Y times a
    /// row of the forward matrix — and every row of that matrix sums to 1. All three therefore
    /// equal Y, all three cube roots equal `cbrt(Y)`, and the lightness row
    /// (0.2104542553 + 0.7936177850 − 0.0040720468) sums to 1 as well. So `L = cbrt(Y)` exactly.
    ///
    /// It is the anchor a chroma ceiling is expressed against: a ceiling stated as a fraction of
    /// *this* moves when the luminance ladder it belongs to moves, instead of being three numbers
    /// that have to be re-typed together.
    static func neutralLightness(relativeLuminance: Double) -> Double {
        signedCubeRoot(relativeLuminance)
    }

    private static func signedCubeRoot(_ value: Double) -> Double {
        value < 0 ? -pow(-value, 1.0 / 3.0) : pow(value, 1.0 / 3.0)
    }

    /// sRGB's transfer curve, the same one WCAG relative luminance uses. Repeated here rather than
    /// reached for across files so this type stays plain arithmetic with no dependencies.
    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}
