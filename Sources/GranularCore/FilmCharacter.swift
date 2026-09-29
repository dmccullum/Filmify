import Foundation

/// A stock's look as a small set of film traits, applied to display-referred
/// sRGB: color edits by hue in OKLab, then per-channel tone curves that carry
/// the matte blacks, highlight roll-off, and shadow/highlight color crossover.
///
/// The values are fitted by Scripts/fit-film-character.py against reference
/// renderings. They describe the look; they are not a lookup table.
struct FilmCharacter: Sendable {
    /// Input positions of the tone-curve knots.
    static let curveKnots: [Double] = [0, 0.125, 0.25, 0.5, 0.75, 1]
    /// OKLab hue centers of the six color sectors, in degrees: red, yellow,
    /// green, cyan, blue, and magenta.
    static let hueCenters: [Double] = [30, 90, 150, 210, 270, 330]

    /// Offsets from the identity curve at each knot, per channel.
    var red: [Double]
    var green: [Double]
    var blue: [Double]
    /// Per hue sector: lightness offset, chroma scale (natural log), and hue
    /// rotation in radians.
    var lightness: [Double]
    var chroma: [Double]
    var hue: [Double]
    /// Chroma change toward the brightest tones (positive desaturates).
    var highlightDesaturation: Double
    /// Chroma change toward the darkest tones (positive saturates).
    var shadowSaturation: Double
}

extension FilmStockID {
    var character: FilmCharacter? {
        switch self {
        case .portra400:
            FilmCharacter(
                red: [0.0343, -0.0253, -0.0050, 0.0500, 0.0172, -0.0712],
                green: [0.0326, -0.0276, 0.0004, 0.0609, 0.0443, -0.0712],
                blue: [0.0190, -0.0158, 0.0023, 0.0554, 0.0282, -0.0467],
                lightness: [-0.0758, -0.0211, -0.0217, -0.0008, -0.0295, -0.0861],
                chroma: [-0.1181, -0.0823, -0.3106, 0.1344, -0.3580, -0.2177],
                hue: [-0.0164, -0.4006, 0.0420, -0.1120, -0.1836, 0.2117],
                highlightDesaturation: -0.1596,
                shadowSaturation: -0.1232
            )
        case .ektar100:
            FilmCharacter(
                red: [-0.0000, -0.0911, -0.0797, -0.0300, 0.0218, -0.0458],
                green: [0.0000, -0.0835, -0.0449, 0.0034, 0.0364, -0.0345],
                blue: [0.0000, -0.0530, -0.0320, 0.0215, 0.0422, -0.0163],
                lightness: [0.0061, -0.0088, -0.0439, -0.0230, 0.0157, 0.0282],
                chroma: [-0.0536, -0.3006, -0.3653, 0.0398, -0.3553, -0.3699],
                hue: [-0.0979, -0.2964, 0.3369, -0.3206, -0.0997, 0.1042],
                highlightDesaturation: 0.0724,
                shadowSaturation: 0.1371
            )
        case .gold200:
            FilmCharacter(
                red: [0.0376, -0.0119, 0.0425, 0.1449, 0.0932, -0.0444],
                green: [0.0431, -0.0104, 0.0435, 0.1681, 0.0947, -0.0687],
                blue: [0.0374, -0.0036, 0.0143, 0.1216, 0.0369, -0.0620],
                lightness: [-0.1397, -0.0031, -0.0227, 0.0170, -0.0638, -0.1870],
                chroma: [-0.3248, 0.0334, -0.4701, 0.2940, -0.3203, -0.4254],
                hue: [0.0455, -0.6605, 0.0051, 0.1987, -0.2110, 0.2083],
                highlightDesaturation: -0.2869,
                shadowSaturation: -0.3790
            )
        case .pro400H:
            FilmCharacter(
                red: [-0.0011, -0.0776, -0.0292, 0.0087, 0.0090, -0.0891],
                green: [0.0042, -0.0471, -0.0129, 0.0152, 0.0140, -0.0880],
                blue: [-0.0008, -0.0624, -0.0140, 0.0230, 0.0242, -0.0647],
                lightness: [-0.0136, -0.0179, 0.0049, 0.0081, -0.0073, -0.0212],
                chroma: [-0.0116, -0.1855, -0.3076, 0.2040, -0.0277, -0.2506],
                hue: [-0.0451, -0.2067, 0.3437, -0.1948, -0.2905, 0.0801],
                highlightDesaturation: 0.2447,
                shadowSaturation: 0.0138
            )
        case .superia400:
            FilmCharacter(
                red: [-0.0031, -0.0748, -0.0242, 0.0707, 0.0982, -0.0475],
                green: [0.0264, -0.0195, 0.0068, 0.0703, 0.0547, -0.0594],
                blue: [0.0427, -0.0206, -0.0026, 0.0832, 0.0736, -0.0566],
                lightness: [0.0143, -0.0635, 0.0056, -0.0530, -0.0122, 0.0014],
                chroma: [-0.0346, -0.2330, -0.6780, -0.9276, -0.3335, -0.4395],
                hue: [0.0296, 0.0085, 0.3290, -0.1984, 0.0502, 0.1230],
                highlightDesaturation: 0.3707,
                shadowSaturation: 0.2751
            )
        case .optima100:
            FilmCharacter(
                red: [0.0086, -0.0559, -0.0196, 0.0683, 0.0813, -0.0431],
                green: [0.0239, -0.0111, 0.0137, 0.0709, 0.0482, -0.0463],
                blue: [0.0326, -0.0107, 0.0064, 0.0815, 0.0588, -0.0428],
                lightness: [0.0078, -0.0486, -0.0076, -0.0331, 0.0081, -0.0053],
                chroma: [-0.0105, -0.1691, -0.7030, -0.4704, -0.2581, -0.4310],
                hue: [0.0334, -0.0360, 0.3486, -0.2074, 0.0291, 0.0890],
                highlightDesaturation: 0.4129,
                shadowSaturation: 0.1972
            )
        case .velvia100F:
            FilmCharacter(
                red: [0.0059, -0.1012, -0.1017, 0.0301, 0.0658, -0.0276],
                green: [-0.0012, -0.1045, -0.0465, 0.0842, 0.0649, -0.0324],
                blue: [0.0033, -0.0694, -0.0169, 0.0943, 0.0932, -0.0277],
                lightness: [0.0092, 0.0122, -0.0552, -0.0026, -0.0215, 0.0283],
                chroma: [0.2428, 0.3679, -0.0096, 0.5970, 0.1849, -0.2095],
                hue: [0.0557, 0.1360, 0.2411, -0.0383, -0.1145, 0.1260],
                highlightDesaturation: 0.0168,
                shadowSaturation: 0.2575
            )
        case .eliteChrome:
            FilmCharacter(
                red: [-0.0000, -0.0970, -0.0650, -0.0192, -0.0254, -0.0641],
                green: [0.0000, -0.0978, -0.0604, 0.0008, -0.0128, -0.0657],
                blue: [-0.0000, -0.0726, -0.0448, 0.0086, -0.0002, -0.0564],
                lightness: [0.0312, 0.0107, -0.0184, -0.0136, 0.0412, 0.0335],
                chroma: [-0.0217, 0.0733, -0.7519, 0.2320, -0.3891, -0.5344],
                hue: [0.2312, -0.0572, -0.0369, 0.0249, 0.1102, 0.0236],
                highlightDesaturation: 0.1018,
                shadowSaturation: 0.2344
            )
        case .e100G:
            FilmCharacter(
                red: [0.0538, -0.0065, -0.0351, -0.0059, 0.0208, -0.0373],
                green: [0.0401, -0.0202, -0.0424, 0.0022, -0.0031, -0.0459],
                blue: [0.0573, 0.0107, -0.0090, 0.0026, 0.0125, -0.0400],
                lightness: [-0.0269, -0.0232, -0.0286, -0.0407, -0.0190, 0.0021],
                chroma: [0.0292, 0.0995, -0.0406, 0.2554, 0.0976, -0.0911],
                hue: [0.1797, 0.0870, 0.2262, -0.0829, 0.2544, 0.1484],
                highlightDesaturation: 0.1403,
                shadowSaturation: -0.1224
            )
        case .e200:
            FilmCharacter(
                red: [0.0006, -0.0751, 0.0223, 0.0991, 0.0468, -0.0284],
                green: [0.0016, -0.0518, 0.0030, 0.0834, 0.0505, -0.0394],
                blue: [0.0011, -0.0476, 0.0046, 0.0758, 0.0431, -0.0386],
                lightness: [-0.0116, -0.0060, -0.0159, -0.0044, 0.0180, 0.0201],
                chroma: [0.0793, 0.0644, -0.8813, -0.3095, -0.3811, -0.4067],
                hue: [0.1576, -0.0405, 0.0904, -0.4488, -0.2883, 0.1036],
                highlightDesaturation: 0.1890,
                shadowSaturation: 0.0450
            )
        case .kodachrome64:
            FilmCharacter(
                red: [0.0399, -0.0101, -0.0080, 0.0047, 0.0315, -0.0043],
                green: [0.0264, -0.0390, -0.0521, -0.0242, 0.0272, 0.0142],
                blue: [0.0389, -0.0173, -0.0370, -0.0078, 0.0429, -0.0038],
                lightness: [-0.0509, -0.0704, -0.1000, -0.0805, 0.0152, -0.0217],
                chroma: [0.0240, -0.2940, -0.7949, -0.0892, -0.2584, -0.6351],
                hue: [0.1662, -0.3042, 0.4654, 0.2854, -0.2446, 0.1791],
                highlightDesaturation: 0.3036,
                shadowSaturation: -0.0988
            )
        case .instax:
            FilmCharacter(
                red: [0.0838, -0.0069, -0.0400, -0.0208, 0.0000, -0.0977],
                green: [0.0515, -0.0023, -0.0104, -0.0031, -0.0294, -0.1217],
                blue: [0.0490, -0.0122, -0.0146, 0.0084, -0.0281, -0.1419],
                lightness: [0.0496, -0.0079, -0.0469, -0.0694, 0.0673, 0.0627],
                chroma: [-0.1295, -0.1455, -0.2427, -0.6438, -0.9687, -0.8730],
                hue: [0.1572, -0.1057, -0.0014, -0.4039, 0.1441, 0.0502],
                highlightDesaturation: 0.3336,
                shadowSaturation: 0.4323
            )
        case .fp100C:
            FilmCharacter(
                red: [0.0620, -0.0237, -0.0032, 0.0425, -0.0307, -0.1583],
                green: [0.0970, -0.0041, -0.0084, 0.0644, -0.0161, -0.1529],
                blue: [0.0752, -0.0210, -0.0144, 0.0721, -0.0161, -0.1448],
                lightness: [-0.0023, -0.0272, -0.0312, -0.0304, 0.0366, 0.0165],
                chroma: [-0.0968, -0.0506, -0.4148, -0.3918, -0.7092, -0.7493],
                hue: [0.2183, -0.1507, 0.1355, 0.0839, 0.1894, -0.0435],
                highlightDesaturation: -0.0741,
                shadowSaturation: 0.2446
            )
        case .triX400:
            FilmCharacter(
                red: [0.0081, -0.1026, -0.1084, -0.0102, 0.0225, -0.0682],
                green: [0.0081, -0.1026, -0.1084, -0.0102, 0.0225, -0.0682],
                blue: [0.0081, -0.1026, -0.1084, -0.0102, 0.0225, -0.0682],
                lightness: [-0.0130, 0.0034, 0.0167, 0.0097, -0.0127, -0.0164],
                chroma: [-6.4335, -9.2118, -4.8602, -6.1386, -5.8492, -4.2312],
                hue: [-0.0519, -0.0857, 0.0473, -0.0026, -0.0484, 0.0161],
                highlightDesaturation: 1.7923,
                shadowSaturation: -2.6334
            )
        case .hp5:
            FilmCharacter(
                red: [0.0322, -0.0259, -0.0333, 0.0431, 0.1077, -0.0236],
                green: [0.0322, -0.0259, -0.0333, 0.0431, 0.1077, -0.0236],
                blue: [0.0322, -0.0259, -0.0333, 0.0431, 0.1077, -0.0236],
                lightness: [-0.0135, 0.0045, 0.0150, 0.0086, -0.0085, -0.0154],
                chroma: [-6.5201, -9.2646, -4.9332, -6.3368, -5.8615, -4.2590],
                hue: [0.0001, -0.0064, 0.0106, 0.0136, 0.0017, -0.0013],
                highlightDesaturation: 2.0118,
                shadowSaturation: -2.0292
            )
        default:
            nil
        }
    }
}
