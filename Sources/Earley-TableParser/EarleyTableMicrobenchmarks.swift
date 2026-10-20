import Foundation
import Grammar
import Parser

/// Engine-owned executable microbenchmarks for both stabilized Earley table traversals.
public enum EarleyTableMicrobenchmarks {
    public static let ownerVersion = "0.2.1"
    public static let inputScale = 24

    private static let grammarSource = """
    <E> ::= <T> <R>
    <R> ::= '+' <T> <R> | ε
    <T> ::= 'id'
    """
    private static var input: String {
        Array(repeating: "id", count: inputScale).joined(separator: " + ")
    }

    public static func suite(
        lookahead: EarleyTableLookahead,
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10
    ) -> ParserEngineMicrobenchmarkSuite {
        .init(
            owner: .init(repository: "Earley-TableParser", version: ownerVersion),
            engineID: lookahead == .simple ? "earley-sl" : "earley-el",
            id: "earley-table-\(lookahead.rawValue)-v1",
            title: "Earley table \(lookahead.rawValue) lookahead workloads",
            buildConfiguration: buildConfiguration,
            warmupIterations: warmupIterations,
            measurementIterations: measurementIterations,
            cases: [.init(
                id: "expression-forest", title: "Build a right-recursive expression forest",
                operation: .forestConstruction,
                boundary: "Tokenize and traverse a pre-built \(lookahead.rawValue)-lookahead table, including BSR/SPPF construction.",
                workloadFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    grammarSource, input, "prebuilt-table", lookahead.rawValue, "bsr-sppf"
                ]),
                scale: inputScale
            )]
        )
    }

    public static func run(
        lookahead: EarleyTableLookahead,
        buildConfiguration: ParserEngineMicrobenchmarkSuite.BuildConfiguration,
        warmupIterations: Int = 2,
        measurementIterations: Int = 10,
        environment: ParserEngineMicrobenchmarkEnvironment = .current
    ) throws -> ParserEngineMicrobenchmarkReport {
        let parser = EarleyTableParser(
            grammar: try Grammar(bnf: grammarSource, start: "E"), lookahead: lookahead
        )
        return try ParserEngineMicrobenchmarkRunner.run(
            suite(
                lookahead: lookahead, buildConfiguration: buildConfiguration,
                warmupIterations: warmupIterations,
                measurementIterations: measurementIterations
            ),
            environment: environment
        ) { _ in
            let result = try parser.parse(input)
            let nodes = result.sppfGraph?.getAllNodes().count ?? 0
            return .init(
                evidenceFingerprint: ParserEngineMicrobenchmarkCodec.evidenceFingerprint([
                    String(result.isSuccessful), String(result.bsr.count), String(nodes)
                ]),
                counters: [
                    "accepted": result.isSuccessful ? 1 : 0,
                    "bsrCount": result.bsr.count, "forestNodeCount": nodes
                ]
            )
        }
    }
}
