import Foundation

struct Lesson: Identifiable, Codable, Equatable {
    let lessonID: String
    let title: String
    let targetDialect: Dialect
    let items: [TrainingItem]

    var id: String { lessonID }

    enum CodingKeys: String, CodingKey {
        case id
        case lessonID = "lesson_id"
        case title
        case targetDialectCamel = "targetDialect"
        case targetDialect = "target_dialect"
        case items
    }

    init(lessonID: String, title: String, targetDialect: Dialect, items: [TrainingItem]) {
        self.lessonID = lessonID
        self.title = title
        self.targetDialect = targetDialect
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lessonID = try container.decodeIfPresent(String.self, forKey: .lessonID)
            ?? container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        targetDialect = (try? container.decodeIfPresent(Dialect.self, forKey: .targetDialect))
            ?? (try? container.decodeIfPresent(Dialect.self, forKey: .targetDialectCamel))
            ?? .northernHanoi
        items = try container.decode([TrainingItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lessonID, forKey: .lessonID)
        try container.encode(title, forKey: .title)
        try container.encode(targetDialect, forKey: .targetDialect)
        try container.encode(items, forKey: .items)
    }
}

struct TrainingItem: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let displayText: String
    let meaning: String?
    let targetDialect: Dialect
    let difficulty: Int
    let category: TrainingCategory
    let expected: ExpectedPronunciation

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case displayText
        case displayTextSnake = "display_text"
        case meaning
        case targetDialect
        case targetDialectSnake = "target_dialect"
        case difficulty
        case category
        case expected
    }

    init(
        id: String,
        text: String,
        displayText: String,
        meaning: String?,
        targetDialect: Dialect,
        difficulty: Int,
        category: TrainingCategory,
        expected: ExpectedPronunciation
    ) {
        self.id = id
        self.text = text
        self.displayText = displayText
        self.meaning = meaning
        self.targetDialect = targetDialect
        self.difficulty = difficulty
        self.category = category
        self.expected = expected
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        displayText = try container.decodeIfPresent(String.self, forKey: .displayText)
            ?? container.decodeIfPresent(String.self, forKey: .displayTextSnake)
            ?? text
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning)
        targetDialect = (try? container.decodeIfPresent(Dialect.self, forKey: .targetDialect))
            ?? (try? container.decodeIfPresent(Dialect.self, forKey: .targetDialectSnake))
            ?? .northernHanoi
        difficulty = try Self.decodeDifficulty(from: container)
        category = (try? container.decodeIfPresent(TrainingCategory.self, forKey: .category)) ?? .toneMinimalPair
        expected = try container.decode(ExpectedPronunciation.self, forKey: .expected)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(displayText, forKey: .displayText)
        try container.encodeIfPresent(meaning, forKey: .meaning)
        try container.encode(targetDialect, forKey: .targetDialect)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(category, forKey: .category)
        try container.encode(expected, forKey: .expected)
    }

    private static func decodeDifficulty(from container: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        if let value = try? container.decodeIfPresent(Int.self, forKey: .difficulty) {
            return value
        }

        guard let value = try? container.decodeIfPresent(String.self, forKey: .difficulty) else {
            return 1
        }

        switch value.lowercased() {
        case "starter", "beginner", "easy":
            return 1
        case "intermediate", "medium":
            return 2
        case "advanced", "hard":
            return 3
        default:
            return Int(value) ?? 1
        }
    }
}

enum Dialect: String, Codable, CaseIterable {
    case northernHanoi = "northern_hanoi"

    var displayName: String {
        switch self {
        case .northernHanoi:
            return "Northern / Hanoi"
        }
    }
}

enum TrainingCategory: String, Codable, CaseIterable {
    case toneMinimalPair = "tone_minimal_pair"
    case vowelContrast = "vowel_contrast"
    case finalConsonant = "final_consonant"
    case shortPhrase = "short_phrase"

    var displayName: String {
        switch self {
        case .toneMinimalPair:
            return "Tone minimal pair"
        case .vowelContrast:
            return "Vowel contrast"
        case .finalConsonant:
            return "Final consonant"
        case .shortPhrase:
            return "Short phrase"
        }
    }
}

struct ExpectedPronunciation: Codable, Equatable {
    let syllables: [VietnameseSyllableTarget]
}

struct VietnameseSyllableTarget: Codable, Equatable {
    let orthography: String
    let initial: String?
    let rime: String
    let finalSound: String?
    let tone: VietnameseTone

    enum CodingKeys: String, CodingKey {
        case orthography
        case initial
        case rime
        case finalSound = "final"
        case tone
    }
}

enum VietnameseTone: String, Codable, CaseIterable {
    case ngang
    case sac
    case huyen
    case hoi
    case nga
    case nang

    var displayName: String {
        switch self {
        case .ngang:
            return "ngang"
        case .sac:
            return "sắc"
        case .huyen:
            return "huyền"
        case .hoi:
            return "hỏi"
        case .nga:
            return "ngã"
        case .nang:
            return "nặng"
        }
    }
}
