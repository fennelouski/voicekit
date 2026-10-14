//
//  DictationPipelineTests.swift
//  DictateKeyboardTests
//
//  The one rule that matters: you never lose what you said.
//

import Testing

@Suite struct DictationPipelineTests {
    @Test func polishedTextIsTypedWithTrailingSpace() async {
        let output = await DictationPipeline.run(raw: "um hello there") { _ in "Hello there." }
        #expect(output.text == "Hello there. ")
        #expect(output.polishFailed == false)
    }

    @Test func failedPolishStillTypesTheLocallyCleanedText() async {
        struct Boom: Error {}
        // TranscriptCleaner drops the filler and re-capitalizes the exposed sentence start.
        let output = await DictationPipeline.run(raw: "um hello there") { _ in throw Boom() }
        #expect(output.text == "Hello there ")
        #expect(output.polishFailed)
    }

    @Test func emptyPolishIsTreatedAsFailureNotAsAnErasedTranscript() async {
        let output = await DictationPipeline.run(raw: "hello") { _ in "   " }
        #expect(output.text == "hello ")
        #expect(output.polishFailed)
    }

    @Test func silenceTypesNothing() async {
        let output = await DictationPipeline.run(raw: "  um  ") { _ in "should not be called" }
        #expect(output.text.isEmpty)
        #expect(output.polishFailed == false)
    }

    @Test func anAnswerToADictatedQuestionIsRejected() async {
        let raw = "what is the capital of france"
        let output = await DictationPipeline.run(raw: raw) { _ in "Paris." }
        #expect(output.text == raw + " ")
        #expect(output.polishFailed)
    }

    @Test func duplicatedPolishKeepsTheOriginalText() async {
        let raw = "can you send me the report by friday"
        let copy = "Can you send me the report by Friday?"
        let output = await DictationPipeline.run(raw: raw) { _ in "\(copy) \(copy)" }
        #expect(output.text == raw + " ")
        #expect(output.polishFailed)
    }

    @Test func japaneseDictationDoesNotInsertAnExtraASCIISpace() async {
        let output = await DictationPipeline.run(raw: "ありがとう") { $0 }
        #expect(output.text == "ありがとう")
        #expect(!output.polishFailed)
    }
}
