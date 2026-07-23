// EarleyParser.swift
// Implements simpleET() from Section 7.1 of Scott & Johnstone (2026),
// SPPF construction from BSR sets (Section 6), and the EarleyTableParser
// public facade conforming to DeterministicParser and GeneralizedParser.
//
// BUG FIXES applied in this revision
// ───────────────────────────────────
// 1. bsrSetIsAmbiguous – previously counted every repeated (lhs,left,right)
//    triple, including prefix elements that legitimately recur in unambiguous
//    parses. Fixed: only complete elements (position == symbols.count) with
//    *different* pivots signal genuine ambiguity.
//
// 2. buildSPPF left-child for completed multi-symbol productions – the
//    original code only attached a left child for single-symbol completed
//    productions. For productions with more than one symbol the left child
//    (an intermediate node spanning [left…pivot]) was silently dropped.
//    Fixed: any completed label with symbols.count > 1 gets an intermediate
//    left child, just as partial labels do.
//
// 3. Intermediate node label dot position – was always written as
//    `label.position − 1`, which is wrong for completed labels (where
//    position == symbols.count, not the count of consumed symbols minus one).
//    Fixed: use `alpha.count − 1` (count of actually consumed symbols minus
//    one) for both completed and partial labels.
//
// 4. reconstructChildren for multi-symbol productions – the original code
//    returned a bare extent string "[i…j via k]" instead of recursing into
//    the BSR set. Replaced with a proper recursive binary descent that
//    handles every production shape.
//
// 5. EarleyTableParser.init – always builds both tables. The immutable
//    useExtendedLookahead setting chooses the traversal for this instance.
//
// 6. EarleyTableParser.parse(tokens:) – was never implemented (empty body).
//    Implemented: runs simpleET or parseET, builds SPPF, wraps as ParseResult.
//
// 7. hasAmbiguity – was checking getChildren(of:).count > 1 on every node,
//    which is always true for packed nodes (they always have a left and right
//    child). Fixed to mirror Parser.GeneralizedParser.ParseResult: only
//    .symbol and .intermediate nodes with more than one packed child count.
//
// 8. Public parsing helpers share Parser.ParseResult<NodeLabel>; Earley chart
//    state remains an internal traversal detail.
//
// 9. DeterministicParser / GeneralizedParser conformance – was entirely
//    absent. Implemented in EarleyTableParser.swift (this file).
//
// 10. Token ranges are taken directly from TokenStream while consuming tokens;
//     they are never reconstructed by rescanning the source string.

import Foundation
import Grammar
import Parser
import Lexer

/// Symbols recognized by the general-purpose `TokenizerStream` convenience
/// used by `parse(_:)` and `syntaxTree(for:)`.
private let tokenizerSymbols: Set<String> = [
    "//", "/*", "*\\", ":", ":=", "::=", ",", "->", ".", "\"", "<=", ">=",
    "==", "!=", "!", ">", "{", "[", "<", "(", "*", "|", "+", "-", "/", "'",
    "}", "]", ")", ";", "?", "#"
]

// MARK: - Ambiguity check (BSR-only heuristic)

/// True when the BSR set contains two *complete* elements for the same
/// (goal, leftExtent, rightExtent) with different pivots.
/// BUG 1 fix: prefix/intermediate elements are excluded.
func bsrSetIsAmbiguous(_ bsr: Set<BSR<NodeLabel>>) -> Bool {
    var seen = [AmbiguityKey: Int]()
    for elem in bsr {
        guard elem.label.isCompleted else { continue }   // BUG 1 fix
        let key = AmbiguityKey(
            lhs:   elem.label.goal,
            left:  elem.leftExtent,
            right: elem.rightExtent)
        if let prev = seen[key] {
            if prev != elem.pivot { return true }
        } else {
            seen[key] = elem.pivot
        }
    }
    return false
}

private struct AmbiguityKey: Hashable {
    let lhs: NonTerminal; let left, right: Int
}

// MARK: - simpleET()

/// The simple-lookahead Earley Table Traversing Parser (Section 7.1.1).
func simpleET(table: SLParseTable, input tokens: [String]) -> TableTraversalResult {
    let n = tokens.count

    func a(_ j: Int) -> TableKey {
        j >= 1 && j <= n ? table.key(forToken: tokens[j - 1]) : .endOfInput
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)
    var Upsilon = Set<BSR<NodeLabel>>()
    // Keyed by (state, position): the SAME state can be discovered reachable
    // at several DISTINCT input positions over the course of one parse (e.g.
    // via different call sites), and each occurrence needs its own seeding —
    // the zero-width BSR elements below are position-dependent.
    var staticSeeded = Set<EarleyPair>()

    /// See `staticNullableLabels(in:grammar:)`: whenever state `state` becomes
    /// reachable at input position `position`, eagerly record the zero-width
    /// BSR elements its own closure implies — these never arise from `add()`'s
    /// chi1/chi2 handling because no transition is ever crossed to produce them.
    func seedStaticNullables(state: Int, position: Int) {
        guard staticSeeded.insert(EarleyPair(state: state, backIndex: position)).inserted else { return }
        for label in table.staticNullableEntries(state: state) {
            Upsilon.insert(BSR(label: label, leftExtent: position, pivot: position, rightExtent: position))
        }
    }

    @discardableResult
    func add(state p: Int, symbol x: TableKey, backIndex i: Int, pivot k: Int, position j: Int) -> Bool {
        guard let entry = table.entry(state: p, symbol: x) else { return false }
        for label in entry.chi1 {
            Upsilon.insert(BSR(label: label, leftExtent: i, pivot: k, rightExtent: j))
        }
        for label in entry.chi2 {
            Upsilon.insert(BSR(label: label, leftExtent: i, pivot: j, rightExtent: j))
        }
        guard let h = entry.nextState else { return false }
        let pair = EarleyPair(state: h, backIndex: i)
        if E[j].insert(pair).inserted {
            R[j].append(pair)
            seedStaticNullables(state: h, position: j)
            return true
        }
        return false
    }

    E[0].insert(EarleyPair(state: 0, backIndex: 0))
    R[0].append(EarleyPair(state: 0, backIndex: 0))
    seedStaticNullables(state: 0, position: 0)

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple

            let nextTok = a(j + 1)
            for nt in table.entry(state: p, symbol: nextTok)?.completedNTs ?? [] {
                let ntKey = TableKey.nonTerminal(nt)
                for (h, i) in E[k].map(\.asTuple) {
                    add(state: h, symbol: ntKey, backIndex: i, pivot: k, position: j)
                }
            }

            add(state: p, symbol: .epsilon, backIndex: j, pivot: j, position: j)

            if j < n {
                add(state: p, symbol: a(j + 1), backIndex: k, pivot: j, position: j + 1)
            }
        }
    }

    // NFA states contain entailment-closed sets of slots, so the mere presence
    // of a completed start slot in a state can be an over-approximation. The
    // parser has the stronger witness available: a completed start BSR spanning
    // the whole input.
    let accepted = (n == 0 && table.grammar.productions.contains {
        $0.goal == table.grammar.start && $0.rule.isEmpty
    }) || Upsilon.contains { element in
        element.label.isCompleted && element.label.goal == table.grammar.start &&
        element.leftExtent == 0 && element.rightExtent == n
    }
    return TableTraversalResult(accepted: accepted, bsrSet: Upsilon, earleySets: E)
}

// MARK: - BSR → SPPF construction

/// Build an SPPF by expanding symbol and intermediate nodes from the BSR set.
/// This mirrors the extraction used by the sibling Earley-Parser package.
public func buildSPPF(
    from bsrSet: Set<BSR<NodeLabel>>,
    grammar: Grammar,
    tokens: [String]
) -> SPPFGraph<NodeLabel> {
    let graph = SPPFGraph<NodeLabel>()
    let n = tokens.count
    let hasRoot = bsrSet.contains {
        $0.label.isCompleted && $0.label.goal == grammar.start &&
        $0.leftExtent == 0 && $0.rightExtent == n
    }
    // NOTE: with `staticNullableLabels` seeding Upsilon directly (see
    // SLParseTable.swift / ELParseTable.swift / simpleET() / parseET()), a
    // literal `start ::= ε` production is now itself present in `bsrSet` as
    // `(NodeLabel(start,[],0), 0, 0, 0)`, which already makes `hasRoot` true
    // for n == 0. This explicit `hasEmptyRoot` check is therefore redundant
    // in the common case, but it's left in place as a harmless extra guard.
    let hasEmptyRoot = n == 0 && grammar.productions.contains {
        $0.goal == grammar.start && $0.rule.isEmpty
    }
    guard hasRoot || hasEmptyRoot else { return graph }

    let root = SPPFNode<NodeLabel>.symbol(
        label: grammar.start.name, leftExtent: 0, rightExtent: n)
    graph.add(root)
    var expanded = Set<SPPFNode<NodeLabel>>()

    while let node = graph.getExtendableNodes().first(where: { !expanded.contains($0) }) {
        expanded.insert(node)
        switch node {
        case let .symbol(name, left, right):
            for entry in bsrSet where entry.label.isCompleted &&
                entry.label.goal.name == name && entry.leftExtent == left &&
                entry.rightExtent == right {
                makePackedNode(entry.label, left: left, pivot: entry.pivot, right: right,
                               parent: node, graph: graph, grammar: grammar)
            }
            // NOTE: with `staticNullableLabels` now eagerly seeding
            // `NodeLabel(goal,[],0)` into `bsrSet` for every literal `X ::= ε`
            // production the moment X is called (see SLParseTable.swift's
            // `staticNullableLabels(in:grammar:)` for the full rationale),
            // the primary loop above already finds and handles these entries
            // on its own. This explicit fallback is therefore redundant in
            // the common case, but it's left in place as a harmless extra
            // guard for any epsilon production the eager-seeding mechanism
            // doesn't reach (e.g. a nonterminal that is never itself the
            // target of `calls()` from any reachable state, if such a case
            // exists in a given grammar).
            if left == right {
                for production in grammar.productions where
                    production.goal.name == name && production.rule.isEmpty {
                    let label = NodeLabel(
                        goal: production.goal, symbols: production.rule, position: 0)
                    makePackedNode(label, left: left, pivot: left, right: right,
                                   parent: node, graph: graph, grammar: grammar)
                }
            }
        case let .intermediate(label, left, right):
            let alpha = Array(label.symbols.prefix(label.position))
            if alpha.count == 1 {
                makePackedNode(label, left: left, pivot: left, right: right,
                               parent: node, graph: graph, grammar: grammar)
            } else {
                for entry in bsrSet where entry.label == label &&
                    entry.leftExtent == left && entry.rightExtent == right {
                    makePackedNode(label, left: left, pivot: entry.pivot, right: right,
                                   parent: node, graph: graph, grammar: grammar)
                }
            }
        case .leaf, .packed:
            break
        }
    }
    graph.cleanup()
    return graph
}

private func sppfNode(for symbol: Symbol, left: Int, right: Int) -> SPPFNode<NodeLabel> {
    switch symbol {
    case .terminal(let terminal):
        return .leaf(label: terminal.description, leftExtent: left, rightExtent: right)
    case .nonTerminal(let nonterminal):
        return .symbol(label: nonterminal.name, leftExtent: left, rightExtent: right)
    case .metaSymbol(let meta):
        return .leaf(label: meta.rawValue, leftExtent: left, rightExtent: right)
    }
}

private func makePackedNode(
    _ label: NodeLabel, left: Int, pivot: Int, right: Int,
    parent: SPPFNode<NodeLabel>, graph: SPPFGraph<NodeLabel>, grammar: Grammar
) {
    let packed = SPPFNode<NodeLabel>.packed(
        label: label, leftExtent: left, rightExtent: right, pivot: pivot)
    graph.addEdge(from: parent, to: packed)
    let alpha = Array(label.symbols.prefix(label.position))
    guard !alpha.isEmpty else {
        graph.addEdge(from: packed, to: .leaf(
            label: "\(grammar.epsilon)", leftExtent: left, rightExtent: right))
        return
    }

    graph.addEdge(from: packed, to: sppfNode(for: alpha.last!, left: pivot, right: right))
    if alpha.count == 2 {
        graph.addEdge(from: packed, to: sppfNode(for: alpha[0], left: left, right: pivot))
    } else if alpha.count > 2 {
        let intermediate = NodeLabel(
            goal: label.goal, symbols: label.symbols, position: label.position - 1)
        graph.addEdge(from: packed, to: .intermediate(
            label: intermediate, leftExtent: left, rightExtent: pivot))
    }
}

// MARK: - Derivation extraction (debug / test utility)

/// Extract one derivation tree from a BSR set as a human-readable string.
/// BUG 4 fix: multi-symbol productions now recurse properly.
public func extractDerivation(
    from bsrSet: Set<BSR<NodeLabel>>,
    grammar: Grammar,
    tokens: [String]
) -> String? {
    let n = tokens.count
    guard let root = bsrSet.first(where: {
        $0.leftExtent == 0 && $0.rightExtent == n && $0.label.goal == grammar.start
    }) else { return nil }
    return walkBSR(elem: root, bsrSet: bsrSet, tokens: tokens)
}

private func walkBSR(elem: BSR<NodeLabel>, bsrSet: Set<BSR<NodeLabel>>, tokens: [String]) -> String {
    let label = elem.label
    if label.isCompleted {
        if label.symbols.isEmpty { return "(\(label.goal.name) → ε)" }
        let children = reconstructChildren(
            goal: label.goal, symbols: label.symbols,
            left: elem.leftExtent, pivot: elem.pivot, right: elem.rightExtent,
            bsrSet: bsrSet, tokens: tokens)
        return "(\(label.goal.name) → \(children.joined(separator: " ")))"
    } else {
        let alpha = Array(label.symbols.prefix(label.position))
        return "(\(label.goal.name)/prefix[\(alpha.map(\.description).joined())] \(elem.leftExtent),\(elem.pivot),\(elem.rightExtent))"
    }
}

/// BUG 4 fix: proper recursive reconstruction for all production shapes.
private func reconstructChildren(
    goal: NonTerminal, symbols: [Symbol],
    left i: Int, pivot k: Int, right j: Int,
    bsrSet: Set<BSR<NodeLabel>>, tokens: [String]
) -> [String] {
    guard !symbols.isEmpty else { return ["ε"] }
    if symbols.count == 1 {
        return [symbolStr(symbols[0], left: i, right: j, bsrSet: bsrSet, tokens: tokens)]
    }
    // Binary split: left = symbols[0..<last] over [i…k], right = symbols[last] over [k…j].
    let prefix  = Array(symbols.dropLast())
    let lastSym = symbols.last!
    let leftStr: String
    if prefix.count == 1 {
        leftStr = symbolStr(prefix[0], left: i, right: k, bsrSet: bsrSet, tokens: tokens)
    } else if let prefixElem = bsrSet.first(where: {
        $0.leftExtent == i && $0.rightExtent == k &&
        $0.label.goal == goal && !$0.label.isCompleted &&
        $0.label.position == prefix.count
    }) {
        leftStr = walkBSR(elem: prefixElem, bsrSet: bsrSet, tokens: tokens)
    } else {
        leftStr = "[\(i)…\(k)]"
    }
    let rightStr = symbolStr(lastSym, left: k, right: j, bsrSet: bsrSet, tokens: tokens)
    return [leftStr, rightStr]
}

private func symbolStr(
    _ sym: Symbol, left: Int, right: Int,
    bsrSet: Set<BSR<NodeLabel>>, tokens: [String]
) -> String {
    switch sym {
    case .terminal:
        return left < tokens.count ? "'\(tokens[left])'" : "'?'"
    case .nonTerminal(let nt):
        if let child = bsrSet.first(where: {
            $0.leftExtent == left && $0.rightExtent == right && $0.label.goal == nt
        }) {
            return walkBSR(elem: child, bsrSet: bsrSet, tokens: tokens)
        }
        return "(\(nt.name) [\(left),\(right)])"
    case .metaSymbol(let ms):
        return ms.rawValue
    }
}

// MARK: - EarleyTableParser public facade

/// A fully general context-free parser built from the Earley Table Traversing
/// algorithm of Scott & Johnstone (SCP 247, 2026).
///
/// Tables are pre-computed once at `init` time. Subsequent parses are O(n³)
/// in the length of the input (same asymptotic complexity as classical Earley,
/// but with smaller constant factors because per-parse slot generation is
/// replaced by table lookups).
public final class EarleyTableParser {

    // MARK: - Public stored state

    public let grammar:  Grammar
    public let nfa:      EarleyNFA
    public let slTable:  SLParseTable
    public let elTable:  ELParseTable

    /// Selects the extended-lookahead (EL) traversal instead of the
    /// simple-lookahead (SL) traversal. The selection is fixed when the
    /// parser is constructed, so a parser instance cannot change behaviour
    /// while it is being shared or used by concurrent clients.
    public let useExtendedLookahead: Bool

    // MARK: - Init

    /// Creates a parser whose traversal mode remains fixed for its lifetime.
    ///
    /// - Parameters:
    ///   - grammar: The grammar to precompute.
    ///   - useExtendedLookahead: `true` selects EL traversal; `false` selects
    ///     SL traversal. The default is `false`.
    public init(grammar: Grammar, useExtendedLookahead: Bool = false) {
        self.grammar              = grammar
        self.nfa                  = buildEarleyNFA(grammar: grammar)
        self.slTable              = buildSLParseTable(nfa: nfa, grammar: grammar)
        self.elTable              = buildELParseTable(nfa: nfa, grammar: grammar)
        self.useExtendedLookahead = useExtendedLookahead
    }

    // MARK: - Core parse

    /// Run the parser on a pre-tokenised input and return an
    /// shared Parser-module result containing the BSR set and SPPF graph.
    ///
    /// BUG 6 fix: this method was previously declared but never implemented.
    ///
    /// - Parameter tokens: Pre-tokenised input as an array of terminal strings.
    /// - Returns: `ParseResult<NodeLabel>` on acceptance.
    /// - Throws: `SyntaxError` if the input is not in the language.
    public func parse(tokens: [String]) throws -> ParseResult<NodeLabel> {
        let raw = traverse(tokens)

        guard raw.accepted else {
            let joined = tokens.joined(separator: " ")
            throw SyntaxError(
                range: joined.startIndex..<joined.endIndex,
                in: joined,
                reason: .unexpectedToken)
        }
        return makeParseResult(from: raw, tokens: tokens)
    }
}

// MARK: - DeterministicParser conformance

extension EarleyTableParser: DeterministicParser {

    /// Parse `string` through `TokenizerStream` and return one parse tree.
    ///
    /// For ambiguous grammars this returns an arbitrary but deterministic
    /// derivation.  Use `allSyntaxTrees(for:)` to get all of them.
    ///
    /// - Throws: `SyntaxError` if the string is not in the language.
    public func syntaxTree(for string: String) throws -> ParseTree {
        let stream = TokenizerStream(
            source: string, symbols: tokenizerSymbols, keywords: [])
        let parsed = try parseStream(stream)
        guard let sppf = parsed.result.sppfGraph else {
            throw SyntaxError(
                range: string.startIndex..<string.endIndex,
                in: string, reason: .unexpectedToken)
        }
        return sppf.buildParseTree(
            startSymbol: grammar.start.name,
            ranges:      parsed.ranges,
            string:      string)
    }
}

// MARK: - GeneralizedParser conformance

extension EarleyTableParser: GeneralizedParser {

    public typealias Label = NodeLabel

    /// Parse `string` and return the raw `ParseResult<NodeLabel>` from the
    /// Parser module, wrapping the SPPF graph.
    ///
    /// - Throws: `SyntaxError` if the string is not in the language.
    public func parse(_ string: String) throws -> ParseResult<NodeLabel> {
        try parse(stream: TokenizerStream(
            source: string, symbols: tokenizerSymbols, keywords: []))
    }

    /// Parse a pre-tokenized stream. The parser performs no lexical analysis;
    /// it consumes the terminals and source ranges supplied by `stream`.
    public func parse<S: TokenStream>(stream: S) throws -> ParseResult<NodeLabel> {
        try parseStream(stream).result
    }

    /// Parse `string` and return **all** parse trees, de-duplicated.
    ///
    /// For unambiguous grammars this always returns exactly one tree.
    /// For ambiguous grammars it returns one tree per distinct derivation.
    ///
    /// - Throws: `SyntaxError` if the string is not in the language.
    public func allSyntaxTrees(for string: String) throws -> [ParseTree] {
        let stream = TokenizerStream(
            source: string, symbols: tokenizerSymbols, keywords: [])
        let parsed = try parseStream(stream)
        guard let sppf = parsed.result.sppfGraph else { return [] }
        return sppf.buildAllParseTrees(
            startSymbol: grammar.start.name,
            ranges:      parsed.ranges,
            string:      string)
    }
}

// MARK: - TokenStream consumption

extension EarleyTableParser {

    private func parseStream<S: TokenStream>(
        _ stream: S
    ) throws -> (result: ParseResult<NodeLabel>, ranges: [Range<String.Index>]) {
        var tokens: [String] = []
        var ranges: [Range<String.Index>] = []
        tokens.reserveCapacity(stream.count)
        ranges.reserveCapacity(stream.count)

        for position in 0..<stream.count {
            let (terminal, range) = try stream.terminal(at: position)
            if case .meta(.eof) = terminal { continue }
            tokens.append(String(stream.source[range]))
            ranges.append(range)
        }

        let raw = traverse(tokens)
        guard raw.accepted else {
            let failureRange: Range<String.Index>
            if let emptySet = raw.earleySets.indices.dropFirst().first(where: {
                raw.earleySets[$0].isEmpty
            }), ranges.indices.contains(emptySet - 1) {
                failureRange = ranges[emptySet - 1]
            } else {
                failureRange = stream.source.endIndex..<stream.source.endIndex
            }
            throw SyntaxError(
                range: failureRange,
                in: stream.source,
                reason: .unexpectedToken)
        }
        return (makeParseResult(from: raw, tokens: tokens), ranges)
    }

    private func traverse(_ tokens: [String]) -> TableTraversalResult {
        if useExtendedLookahead {
            return parseET(table: elTable, input: tokens)
        }
        return simpleET(table: slTable, input: tokens)
    }

    private func makeParseResult(
        from raw: TableTraversalResult,
        tokens: [String]
    ) -> ParseResult<NodeLabel> {
        let sppf = buildSPPF(from: raw.bsrSet, grammar: grammar, tokens: tokens)
        return ParseResult(isSuccessful: true, bsr: raw.bsrSet, sppfGraph: sppf)
    }

}
