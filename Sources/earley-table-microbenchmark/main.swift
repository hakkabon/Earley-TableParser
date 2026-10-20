import Earley_TableParser
import Foundation
import Parser

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard (1...2).contains(arguments.count),
          ["simple", "extended"].contains(arguments[0]) else {
        throw NSError(
            domain: "earley-table-microbenchmark", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "usage: earley-table-microbenchmark simple|extended [output.json]"]
        )
    }
    let lookahead: EarleyTableLookahead = arguments[0] == "extended" ? .extended : .simple
    let output = arguments.dropFirst().first
    #if DEBUG
    let configuration = ParserEngineMicrobenchmarkSuite.BuildConfiguration.debug
    #else
    let configuration = ParserEngineMicrobenchmarkSuite.BuildConfiguration.release
    #endif
    let report = try EarleyTableMicrobenchmarks.run(
        lookahead: lookahead, buildConfiguration: configuration
    )
    let data = try ParserEngineMicrobenchmarkCodec.encode(report)
    if let output {
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
} catch {
    FileHandle.standardError.write(Data("earley-table-microbenchmark: \(error)\n".utf8))
    exit(1)
}
