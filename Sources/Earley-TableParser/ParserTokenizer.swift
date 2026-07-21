// ParserTokenizer.swift
// Bridges a `TokenStream` (from the Lexer module) to the `[String]` token
// arrays that simpleET / parseET / buildSPPF / extractDerivation work with.
//
// All public helpers return the shared Parser-module ParseResult. Earley sets
// remain private traversal state.

import Foundation
import Grammar
import Parser
import Lexer

/// Extract per-position ACTION/GOTO table keys from `stream`.
/// MetaTerminal.eof tokens are dropped: the parser synthesises its own "$".
///
/// - Throws: whatever error `stream.terminal(at:)` raises for a lexical failure.
public func tokenStrings<S: TokenStream>(from stream: S) throws -> [String] {
    var tokens: [String] = []
    tokens.reserveCapacity(stream.count)
    for position in 0..<stream.count {
        let (terminal, range) = try stream.terminal(at: position)
        if case .meta(.eof) = terminal { continue }
        tokens.append(String(stream.source[range]))
    }
    return tokens
}

/// Consume `stream`, run `simpleET`, and build its SPPF.
public func tokenizeAndParse<S: TokenStream>(
    stream: S,
    table: SLParseTable
) throws -> ParseResult<NodeLabel> {
    let tokens = try tokenStrings(from: stream)
    let raw = simpleET(table: table, input: tokens)
    guard raw.accepted else {
        return ParseResult(isSuccessful: false, bsr: raw.bsrSet, sppfGraph: nil)
    }
    let sppf = buildSPPF(from: raw.bsrSet, grammar: table.grammar, tokens: tokens)
    return ParseResult(isSuccessful: true, bsr: raw.bsrSet, sppfGraph: sppf)
}

/// Tokenise `input` with a `TokenizerStream` and run `simpleET` against `table`.
public func tokenizeAndParse(
    input: String,
    table: SLParseTable,
    symbols:  Set<String> = [],
    keywords: Set<String> = []
) throws -> ParseResult<NodeLabel> {
    try tokenizeAndParse(
        stream: TokenizerStream(source: input, symbols: symbols, keywords: keywords),
        table: table
    )
}

/// Tokenise `stream`, run `simpleET`, build SPPF, and return the generic
/// `ParseResult<NodeLabel>` from the Parser module (GeneralizedParser semantics).
@available(*, deprecated, renamed: "tokenizeAndParse(stream:table:)")
public func tokenizeAndParseGeneral<S: TokenStream>(
    stream: S,
    table: SLParseTable,
    grammar: Grammar
) throws -> ParseResult<NodeLabel> {
    precondition(grammar == table.grammar, "The table and grammar must agree")
    return try tokenizeAndParse(stream: stream, table: table)
}
