import Parser
import Testing
@testable import Earley_TableParser

@Test("Each Earley table lookahead owns a reproducible executable microbenchmark", arguments: EarleyTableLookahead.allCases)
func earleyTableMicrobenchmark(lookahead: EarleyTableLookahead) throws {
    let report = try EarleyTableMicrobenchmarks.run(
        lookahead: lookahead,
        buildConfiguration: .release, warmupIterations: 0, measurementIterations: 3,
        environment: .init(
            operatingSystem: "test", architecture: "test",
            processorCount: 1, physicalMemoryBytes: 1
        )
    )
    #expect(report.suite.owner.repository == "Earley-TableParser")
    #expect(report.suite.engineID == (lookahead == .simple ? "earley-sl" : "earley-el"))
    #expect(report.results.first?.counters["accepted"] == 1)
    #expect((report.results.first?.counters["forestNodeCount"] ?? 0) > 0)
}
