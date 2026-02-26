import Testing
@testable import HexCore

struct YearWordConverterTests {
	@Test
	func convertsNineteenHundreds() {
		#expect(YearWordConverter.apply("nineteen eighty four") == "1984")
		#expect(YearWordConverter.apply("in nineteen ninety nine") == "in 1999")
	}

	@Test
	func convertsTwentyHundreds() {
		#expect(YearWordConverter.apply("twenty ten") == "2010")
		#expect(YearWordConverter.apply("twenty twenty one") == "2021")
		#expect(YearWordConverter.apply("twenty thirty five") == "2035")
	}

	@Test
	func convertsLeadingZeroYearTails() {
		#expect(YearWordConverter.apply("twenty oh five") == "2005")
		#expect(YearWordConverter.apply("nineteen zero seven") == "1907")
	}

	@Test
	func doesNotConvertAmbiguousShortForms() {
		#expect(YearWordConverter.apply("twenty one pilots") == "twenty one pilots")
		#expect(YearWordConverter.apply("twenty apples") == "twenty apples")
	}

	@Test
	func preservesPunctuationAndMixedText() {
		#expect(YearWordConverter.apply("Release: twenty twenty four.") == "Release: 2024.")
		#expect(YearWordConverter.apply("Between nineteen eighty four, and twenty twenty one") == "Between 1984, and 2021")
	}
}
