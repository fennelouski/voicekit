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
}
