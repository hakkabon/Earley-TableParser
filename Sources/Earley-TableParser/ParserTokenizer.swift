// ParserTokenizer.swift
// Bridges a `TokenStream` (from the Lexer module) to the `[String]` token
// arrays that simpleET / parseET / buildSPPF / extractDerivation work with.
//
// BUG 8 fix: tokenizeAndParse previously returned `ParseResult` (the generic
// Parser-module type).  It now returns `EarleyTableParseResult` — the correct
// concrete type from this package.  The old signature was wrong because
// `ParseResult<Label>` has no `earleySets` field, and callers that needed
// Earley-set data had no way to access it.
//
// tokenizeAndParseGeneral() is a new overload that returns the generic
// ParseResult<NodeLabel> when the caller needs GeneralizedParser semantics
// without going through the EarleyTableParser facade.

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

/// Tokenise `stream` and run `simpleET` against `table`.
///
/// BUG 8 fix: return type corrected to `EarleyTableParseResult`.
public func tokenizeAndParse<S: TokenStream>(
    stream: S,
    table: SLParseTable
) throws -> EarleyTableParseResult {       // BUG 8 fix: was ParseResult
    let tokens = try tokenStrings(from: stream)
    return simpleET(table: table, input: tokens)
}

/// Tokenise `input` with a `TokenizerStream` and run `simpleET` against `table`.
///
/// BUG 8 fix: return type corrected to `EarleyTableParseResult`.
public func tokenizeAndParse(
    input: String,
    table: SLParseTable,
    symbols:  Set<String> = [],
    keywords: Set<String> = []
) throws -> EarleyTableParseResult {       // BUG 8 fix: was ParseResult
    try tokenizeAndParse(
        stream: TokenizerStream(source: input, symbols: symbols, keywords: keywords),
        table: table
    )
}

/// Tokenise `stream`, run `simpleET`, build SPPF, and return the generic
/// `ParseResult<NodeLabel>` from the Parser module (GeneralizedParser semantics).
public func tokenizeAndParseGeneral<S: TokenStream>(
    stream: S,
    table: SLParseTable,
    grammar: Grammar
) throws -> ParseResult<NodeLabel> {
    let tokens = try tokenStrings(from: stream)
    let raw    = simpleET(table: table, input: tokens)
    guard raw.accepted else {
        return ParseResult(isSuccessful: false, bsr: [], sppfGraph: nil)
    }
    let sppf = buildSPPF(from: raw.bsrSet, grammar: grammar, tokens: tokens)
    return ParseResult(isSuccessful: true, bsr: raw.bsrSet, sppfGraph: sppf)
}
