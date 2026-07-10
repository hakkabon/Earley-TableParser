// ParserTokenizer.swift
// Bridges a `TokenStream` (from the Lexer module) to the `[String]` token
// arrays `simpleET`/`buildSPPF`/`extractDerivation` (EarleyParser.swift) work
// with.
//
// `simpleET` (Section 7.1, Scott & Johnstone) is parameterised purely on
// `[String]` ACTION/GOTO-table keys and integer token-index extents — it
// never needs a `Range<String.Index>` — so extracting each position's exact
// source text is the full extent of what any `TokenStream` front end needs
// to supply here. Both the DFA-driven `LexerTokenStream` (built via a
// `LexerBuilder` bootstrapped from a `GrammarVocabulary`) and the
// hand-written `TokenizerStream` work identically through this bridge.

import Foundation
import Grammar
import Lexer

/// Extracts the ACTION/GOTO-table key for each position in `stream`: the
/// exact source text of its range, with `Terminal.meta(.eof)` dropped (the
/// table lookup functions in `EarleyParser.swift` synthesise their own `"$"`
/// end-of-input key via `eofKey`/`a(n+1)`, so no explicit sentinel is
/// appended here).
///
/// - Throws: whatever error `stream.terminal(at:)` throws for a lexical failure.
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

/// Tokenizes `stream` and runs `simpleET` against `table`.
///
/// - Parameter stream: A positioned sequence of tokens, each resolvable to a
///   `Terminal` and a source `Range<String.Index>` — e.g. a `LexerTokenStream`
///   or a `TokenizerStream`.
public func tokenizeAndParse<S: TokenStream>(stream: S, table: SLParseTable) throws -> ParseResult {
    let tokens = try tokenStrings(from: stream)
    guard !tokens.isEmpty else {
        return ParseResult(accepted: false, bsrSet: [], earleySets: [], sppfGraph: nil)
    }
    return simpleET(table: table, input: tokens)
}

/// Tokenizes `input` with a `TokenizerStream` configured from `symbols`/
/// `keywords`, then runs `simpleET` against `table`.
public func tokenizeAndParse(
    input: String,
    table: SLParseTable,
    symbols: Set<String> = [],
    keywords: Set<String> = []
) throws -> ParseResult {
    try tokenizeAndParse(
        stream: TokenizerStream(source: input, symbols: symbols, keywords: keywords),
        table: table
    )
}
