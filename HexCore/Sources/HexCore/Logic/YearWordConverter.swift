import Foundation

/// Converts spoken year phrases to 4-digit years.
/// Conservative default scope: 1900...2099.
/// Examples:
/// - "nineteen eighty four" -> "1984"
/// - "twenty twenty one" -> "2021"
/// - "twenty oh five" -> "2005"
public enum YearWordConverter {
	private static let ones: [String: Int] = [
		"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
		"five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
		"ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
		"fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
		"eighteen": 18, "nineteen": 19
	]

	private static let tens: [String: Int] = [
		"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
		"sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
	]

	private static let centuryPrefixes: [String: Int] = [
		"nineteen": 1900,
		"twenty": 2000
	]

	private static let leadingZeroWords: Set<String> = ["oh", "zero"]

	public static func apply(_ text: String) -> String {
		guard !text.isEmpty else { return text }

		let tokens = tokenize(text)
		var result: [String] = []
		var i = 0

		while i < tokens.count {
			let token = tokens[i]
			let lower = token.lowercased()

			if centuryPrefixes[lower] != nil {
				let (consumed, yearText) = parseYearSequence(tokens: tokens, startIndex: i)
				if consumed > 0, let yearText {
					result.append(yearText)
					i += consumed
					continue
				}
			}

			result.append(token)
			i += 1
		}

		return result.joined()
	}

	private enum TokenType {
		case word
		case whitespace
		case punctuation
	}

	private static func tokenType(for char: Character) -> TokenType {
		if char.isWhitespace {
			return .whitespace
		} else if char.isLetter || char == "-" || char == "'" {
			return .word
		} else {
			return .punctuation
		}
	}

	private static func tokenize(_ text: String) -> [String] {
		var tokens: [String] = []
		var currentToken = ""
		var currentType: TokenType?

		for char in text {
			let charType = tokenType(for: char)
			if charType == currentType {
				currentToken.append(char)
			} else {
				if !currentToken.isEmpty {
					tokens.append(currentToken)
				}
				currentToken = String(char)
				currentType = charType
			}
		}

		if !currentToken.isEmpty {
			tokens.append(currentToken)
		}

		return tokens
	}

	private struct TailParseResult {
		let value: Int
		let explicitLeadingZero: Bool
	}

	private static func parseYearSequence(tokens: [String], startIndex: Int) -> (Int, String?) {
		guard let base = centuryPrefixes[tokens[startIndex].lowercased()] else {
			return (0, nil)
		}

		// Collect contiguous word tokens separated by whitespace.
		var wordIndices: [Int] = [startIndex]
		var i = startIndex + 1
		while wordIndices.count < 4 && i < tokens.count {
			if tokens[i].allSatisfy({ $0.isWhitespace }) {
				i += 1
				continue
			}
			if isWordToken(tokens[i]) {
				wordIndices.append(i)
				i += 1
				continue
			}
			break
		}

		guard wordIndices.count >= 2 else { return (0, nil) }

		// Prefer longest valid match.
		for count in stride(from: wordIndices.count, through: 2, by: -1) {
			let words = wordIndices[0..<count].map { tokens[$0].lowercased() }
			let tailWords = words.dropFirst().flatMap(expandHyphenated)
			guard let tail = parseTail(Array(tailWords)) else { continue }

			// Keep "twenty" conservative: avoid converting short ambiguous forms like "twenty one".
			if base == 2000 && tail.value < 10 && !tail.explicitLeadingZero {
				continue
			}

			let year = base + tail.value
			guard (1900...2099).contains(year) else { continue }

			let consumed = wordIndices[count - 1] - startIndex + 1
			return (consumed, String(year))
		}

		return (0, nil)
	}

	private static func isWordToken(_ token: String) -> Bool {
		token.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
	}

	private static func expandHyphenated(_ word: String) -> [String] {
		let parts = word.split(separator: "-").map(String.init)
		return parts.isEmpty ? [word] : parts
	}

	private static func parseTail(_ words: [String]) -> TailParseResult? {
		guard !words.isEmpty else { return nil }

		if words.count == 2,
			leadingZeroWords.contains(words[0]),
			let digit = ones[words[1]],
			(0...9).contains(digit)
		{
			return TailParseResult(value: digit, explicitLeadingZero: true)
		}

		if words.count == 1 {
			if let teenOrTens = parseTeenOrTens(words[0]) {
				return TailParseResult(value: teenOrTens, explicitLeadingZero: false)
			}
			return nil
		}

		if words.count == 2,
			let tensValue = tens[words[0]],
			let onesValue = ones[words[1]],
			(1...9).contains(onesValue)
		{
			return TailParseResult(value: tensValue + onesValue, explicitLeadingZero: false)
		}

		return nil
	}

	private static func parseTeenOrTens(_ word: String) -> Int? {
		if let teen = ones[word], (10...19).contains(teen) {
			return teen
		}
		if let tensValue = tens[word] {
			return tensValue
		}
		return nil
	}
}
