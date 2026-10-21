import Foundation

// 名称拆成音节：汉字一字一个拼音音节，其余连续字符按分词结果各算一个
enum SearchName {
    static func syllables(of name: String) -> [String] {
        let source = name as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil,
            source,
            CFRange(location: 0, length: CFStringGetLength(source)),
            kCFStringTokenizerUnitWord,
            Locale(identifier: "zh-Hans") as CFLocale
        )
        var result: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = CFStringCreateWithSubstring(nil, source, range) as String
            let hans = token.filter(\.isHan)
            if hans.isEmpty {
                result.append(normalized(token))
                continue
            }
            let word = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) as? String
            result += split(word.map(normalized) ?? "", readings: hans.map { normalized(String($0).mandarinLatin) })
        }
        return result.filter { !$0.isEmpty }
    }

    static func normalized(_ text: String) -> String {
        (text.applyingTransform(.stripDiacritics, reverse: false) ?? text)
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "'" }
    }

    // 逐字拼音会读错多音字（音乐读成 yin le），按词读音拆回每个字；对不齐时退回逐字拼音
    private static func split(_ word: String, readings: [String]) -> [String] {
        let letters = Array(word)
        let count = readings.count
        guard !letters.isEmpty, letters.count >= count else {
            return readings
        }
        // best[i][j]：前 i 个字用掉前 j 个字母时，与逐字拼音一致的字数
        var best = Array(repeating: Array(repeating: -1, count: letters.count + 1), count: count + 1)
        var cut = best
        best[0][0] = 0
        for i in 0 ..< count {
            for j in 0 ..< letters.count where best[i][j] >= 0 {
                for end in (j + 1) ... letters.count {
                    let score = best[i][j] + (String(letters[j ..< end]) == readings[i] ? 1 : 0)
                    if score > best[i + 1][end] {
                        best[i + 1][end] = score
                        cut[i + 1][end] = j
                    }
                }
            }
        }
        guard best[count][letters.count] >= 0 else {
            return readings
        }
        var parts: [String] = []
        var end = letters.count
        for i in stride(from: count, to: 0, by: -1) {
            let start = cut[i][end]
            parts.insert(String(letters[start ..< end]), at: 0)
            end = start
        }
        // 相邻两个字都对不上时切分位置没有依据
        let mismatched = zip(parts, readings).map { $0 != $1 }
        if zip(mismatched, mismatched.dropFirst()).contains(where: { $0 && $1 }) {
            return readings
        }
        return parts
    }
}

private extension Character {
    var isHan: Bool {
        unicodeScalars.contains { $0.properties.isIdeographic }
    }
}

private extension String {
    var mandarinLatin: String {
        applyingTransform(.mandarinToLatin, reverse: false) ?? self
    }
}
