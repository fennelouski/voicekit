import Testing
@testable import VoiceKitEvaluate

struct MetricsTests {
    @Test func casePunctuationAndCanonicalUnicodeDoNotCountAsErrors() {
        let score = EvaluationMetrics.score(reference: "Hello, café!", hypothesis: "hello CAFE\u{301}")
        #expect(score.wordErrorRate == 0 && score.characterErrorRate == 0)
    }
    @Test func substitutionsDeletionsAndInsertionsCount() {
        let score = EvaluationMetrics.score(reference: "one two three", hypothesis: "one four three five")
        #expect(score.wordEdits == 2 && score.referenceWords == 3)
        #expect(abs(score.wordErrorRate - 2.0 / 3.0) < 0.0001)
    }
    @Test func emptyReferenceReportsInsertionsWithoutNaN() {
        let score = EvaluationMetrics.score(reference: "", hypothesis: "hallucination")
        #expect(score.wordErrorRate == 1 && score.characterErrorRate == 13)
        #expect(EvaluationMetrics.score(reference: "", hypothesis: "").wordErrorRate == 0)
    }
    @Test func characterErrorSupportsUnspacedScripts() {
        let score = EvaluationMetrics.score(reference: "今天天气很好", hypothesis: "今天天气好")
        #expect(score.characterEdits == 1 && score.referenceCharacters == 6)
    }
}
