import Foundation

/// Converts spoken cardinal number words to numeric digits.
/// Example: "twenty five" → "25", "one thousand three hundred thirty six" → "1336"
/// Preserves word boundaries (someone, threesome).
public enum NumberWordConverter {
	// MARK: - Number Word Mappings

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

	private static let scales: [String: Int] = [
		"hundred": 100,
		"thousand": 1000,
		"million": 1_000_000,
		"billion": 1_000_000_000,
		"trillion": 1_000_000_000_000
	]

	/// Words that are part of number expressions but not numbers themselves
	private static let connectors: Set<String> = ["and"]

	// MARK: - Public API

	/// Converts number words to digits in the given text.
	/// - Parameter text: The input text containing number words
	/// - Returns: Text with number words converted to digits
	public static func apply(_ text: String) -> String {
		guard !text.isEmpty else { return text }

		let tokens = tokenize(text)
		var result: [String] = []
		var i = 0

		while i < tokens.count {
			let token = tokens[i]
			let lower = token.lowercased()

			// Check if this token starts a number sequence
			if isNumberWord(lower) || isLeadingDecimalMarker(tokens: tokens, at: i) {
				let (numberTokens, value, hasDecimal, decimalValue) = parseNumberSequence(tokens: tokens, startIndex: i)

				if numberTokens > 0 {
					// Format the number
					if hasDecimal {
						result.append(formatDecimal(value, decimalValue))
					} else {
						result.append(String(value))
					}
					i += numberTokens
					continue
				}
			}

			// Not a number word, keep as-is
			result.append(token)
			i += 1
		}

		return result.joined()
	}

	// MARK: - Tokenization

	/// Tokenizes text into words, whitespace, and punctuation, preserving everything.
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

	private enum TokenType {
		case word
		case whitespace
		case punctuation
	}

	private enum ParsedKind {
		case ones
		case tens
		case scale
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

	// MARK: - Number Parsing

	/// Checks if a word (lowercased) is a number word.
	private static func isNumberWord(_ word: String) -> Bool {
		// Handle hyphenated numbers like "twenty-five"
		let parts = word.split(separator: "-").map { String($0) }
		if parts.count == 2 {
			return isNumberWord(parts[0]) && isNumberWord(parts[1])
		}

		return ones[word] != nil || tens[word] != nil || scales[word] != nil
	}

	private static func isDecimalDigitWord(_ word: String) -> Bool {
		if let value = ones[word] {
			return (0...9).contains(value)
		}
		return false
	}

	private static func nextNonWhitespaceIndex(tokens: [String], from index: Int) -> Int? {
		var i = index
		while i < tokens.count {
			if tokens[i].allSatisfy({ $0.isWhitespace }) {
				i += 1
				continue
			}
			return i
		}
		return nil
	}

	private static func isLeadingDecimalMarker(tokens: [String], at index: Int) -> Bool {
		guard tokens[index].lowercased() == "point" else { return false }
		guard let next = nextNonWhitespaceIndex(tokens: tokens, from: index + 1) else { return false }
		return isDecimalDigitWord(tokens[next].lowercased())
	}

	private static func trimTrailingWhitespace(tokens: [String], startIndex: Int, consumedCount: Int) -> Int {
		var trimmed = consumedCount
		while trimmed > 0 {
			let token = tokens[startIndex + trimmed - 1]
			if token.allSatisfy({ $0.isWhitespace }) {
				trimmed -= 1
			} else {
				break
			}
		}
		return trimmed
	}

	/// Parses a sequence of number words starting at the given index.
	/// Returns: (tokensConsumed, integerValue, hasDecimal, decimalString)
	private static func parseNumberSequence(tokens: [String], startIndex: Int) -> (Int, Int, Bool, String) {
		var tokensConsumed = 0
		var currentValue = 0
		var total = 0
		var lastWasNumber = false
		var i = startIndex

		// Track decimal part
		var hasDecimal = false
		var decimalString = ""
		var inDecimal = false

		// Conservative parsing guards
		var sawScaleInSequence = false
		var lastParsedKind: ParsedKind?

		while i < tokens.count {
			let token = tokens[i]
			let lower = token.lowercased()

			// Skip whitespace between number words
			if token.allSatisfy({ $0.isWhitespace }) {
				if lastWasNumber || inDecimal {
					guard let nextIndex = nextNonWhitespaceIndex(tokens: tokens, from: i + 1) else { break }
					let nextLower = tokens[nextIndex].lowercased()
					let canContinue: Bool
					if inDecimal {
						canContinue = isDecimalDigitWord(nextLower)
					} else {
						canContinue = isNumberWord(nextLower) || nextLower == "point" || (connectors.contains(nextLower) && sawScaleInSequence)
					}
					if canContinue {
						tokensConsumed += 1
						i += 1
						continue
					}
				}
				break
			}

			// Handle "point" for decimals, including leading decimals ("point five")
			if lower == "point" && !inDecimal {
				let canStartDecimal = lastWasNumber || tokensConsumed == 0
				guard canStartDecimal else { break }

				if let nextIndex = nextNonWhitespaceIndex(tokens: tokens, from: i + 1),
					isDecimalDigitWord(tokens[nextIndex].lowercased())
				{
					inDecimal = true
					hasDecimal = true
					tokensConsumed += 1
					i += 1
					lastWasNumber = false
					continue
				}

				// Trailing decimal marker with no digits ("one point"):
				// consume marker and keep integer part as-is.
				if lastWasNumber {
					tokensConsumed += 1
					i += 1
				}
				break
			}

			// Handle decimal digits (after "point")
			if inDecimal {
				if let digitValue = ones[lower], (0...9).contains(digitValue) {
					decimalString.append(String(digitValue))
					tokensConsumed += 1
					i += 1
					lastWasNumber = true
					continue
				} else {
					// End of decimal
					break
				}
			}

			// Handle connectors like "and" (conservative: only in scale contexts)
			if connectors.contains(lower) && lastWasNumber && sawScaleInSequence {
				guard let nextIndex = nextNonWhitespaceIndex(tokens: tokens, from: i + 1), isNumberWord(tokens[nextIndex].lowercased()) else {
					break
				}
				tokensConsumed += 1
				i += 1
				continue
			}

			// Handle hyphenated numbers like "twenty-five"
			let parts = lower.split(separator: "-").map { String($0) }
			if parts.count == 2, let tensVal = tens[parts[0]], let onesVal = ones[parts[1]] {
				currentValue += tensVal + onesVal
				tokensConsumed += 1
				i += 1
				lastWasNumber = true
				lastParsedKind = .tens
				continue
			}

			// Handle ones (0-19)
			if let value = ones[lower] {
				// Avoid merging ambiguous multi-number sequences like "one and two" or "twenty twenty one"
				if let lastParsedKind, lastParsedKind == .ones, !sawScaleInSequence, tokensConsumed > 0 {
					break
				}
				currentValue += value
				tokensConsumed += 1
				i += 1
				lastWasNumber = true
				lastParsedKind = .ones
				continue
			}

			// Handle tens (20, 30, ... 90)
			if let value = tens[lower] {
				// Keep default mode conservative: don't collapse adjacent tens into one number.
				if let lastParsedKind, lastParsedKind == .tens, !sawScaleInSequence, tokensConsumed > 0 {
					break
				}
				currentValue += value
				tokensConsumed += 1
				i += 1
				lastWasNumber = true
				lastParsedKind = .tens
				continue
			}

			// Handle scales (hundred, thousand, million, billion)
			if let scale = scales[lower] {
				if scale == 100 {
					// "hundred" multiplies current value
					currentValue = (currentValue == 0 ? 1 : currentValue) * 100
				} else {
					// thousand/million/billion: multiply current group and add to total
					let groupValue = (currentValue == 0 ? 1 : currentValue) * scale
					total += groupValue
					currentValue = 0
				}
				tokensConsumed += 1
				i += 1
				lastWasNumber = true
				sawScaleInSequence = true
				lastParsedKind = .scale
				continue
			}

			// Not a number word
			break
		}

		total += currentValue

		let effectiveConsumed = trimTrailingWhitespace(tokens: tokens, startIndex: startIndex, consumedCount: tokensConsumed)

		// Only return consumed tokens if we actually parsed a number
		if effectiveConsumed > 0 && (hasDecimal || total > 0 || (effectiveConsumed == 1 && tokens[startIndex].lowercased() == "zero")) {
			return (effectiveConsumed, total, hasDecimal, decimalString)
		}

		return (0, 0, false, "")
	}

	/// Formats a decimal number.
	private static func formatDecimal(_ intPart: Int, _ decimalPart: String) -> String {
		if decimalPart.isEmpty {
			return "\(intPart)"
		}
		return "\(intPart).\(decimalPart)"
	}
}
