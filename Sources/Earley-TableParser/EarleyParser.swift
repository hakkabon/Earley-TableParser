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
// 5. EarleyTableParser.init – always builds both tables regardless of
//    useExtendedLookahead (tables are cheap to compute once and store).
//    parse(tokens:) picks at call time.
//
// 6. EarleyTableParser.parse(tokens:) – was never implemented (empty body).
//    Implemented: runs simpleET or parseET, builds SPPF, wraps as ParseResult.
//
// 7. hasAmbiguity – was checking getChildren(of:).count > 1 on every node,
//    which is always true for packed nodes (they always have a left and right
//    child). Fixed to mirror Parser.GeneralizedParser.ParseResult: only
//    .symbol and .intermediate nodes with more than one packed child count.
//
// 8. tokenizeAndParse return type – was ParseResult (Parser module generic)
//    instead of EarleyTableParseResult. Corrected.
//
// 9. DeterministicParser / GeneralizedParser conformance – was entirely
//    absent. Implemented in EarleyTableParser.swift (this file).
//
// 10. Token-range mapping for ParseTree leaves – SPPFGraph.buildParseTree /
//     buildAllParseTrees (TreeBuilder.swift in the Parser module) require a
//     [Range<String.Index>] per-token array. tokenRanges(for:in:) builds it
//     by scanning the input string for each whitespace-separated token.

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
public func simpleET(table: SLParseTable, input tokens: [String]) -> EarleyTableParseResult {
    let n = tokens.count

    func a(_ j: Int) -> String {
        j >= 1 && j <= n ? table.resolveKey(forToken: tokens[j - 1]) : eofKey
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)
    var Upsilon = Set<BSR<NodeLabel>>()

    @discardableResult
    func add(state p: Int, symbol x: String, backIndex i: Int, pivot k: Int, position j: Int) -> Bool {
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
            return true
        }
        return false
    }

    E[0].insert(EarleyPair(state: 0, backIndex: 0))
    R[0].append(EarleyPair(state: 0, backIndex: 0))

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple

            if k != j {
                let nextTok = a(j + 1)
                for nt in table.entry(state: p, symbol: nextTok)?.completedNTs ?? [] {
                    let ntKey = nonTerminalKey(nt)
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: ntKey, backIndex: i, pivot: k, position: j)
                    }
                }
            }

            add(state: p, symbol: epsilonKey, backIndex: j, pivot: j, position: j)

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
    return EarleyTableParseResult(accepted: accepted, bsrSet: Upsilon, earleySets: E, sppfGraph: nil)
}

// MARK: - BSR → SPPF construction

/// Build an SPPF graph from a BSR set.
/// BUG 2 & 3 fix: left-child construction is now correct for all label shapes.
private func legacyBuildSPPF(
    from bsrSet: Set<BSR<NodeLabel>>,
    grammar: Grammar,
    tokens: [String]
) -> SPPFGraph<NodeLabel> {
    let graph = SPPFGraph<NodeLabel>()
    let n = tokens.count

    // Index: (goal, left, right) → [BSR element]
    var byKey: [SPPFLookupKey: [BSR<NodeLabel>]] = [:]
    for elem in bsrSet {
        byKey[SPPFLookupKey(lhs: elem.label.goal, left: elem.leftExtent, right: elem.rightExtent),
              default: []].append(elem)
    }

    var processed = Set<SPPFLookupKey>()

    func symNode(lhs: NonTerminal, left: Int, right: Int) -> SPPFNode<NodeLabel> {
        let n = SPPFNode<NodeLabel>.symbol(label: lhs.name, leftExtent: left, rightExtent: right)
        graph.add(n)
        return n
    }

    func populate(lhs: NonTerminal, left: Int, right: Int) {
        let key = SPPFLookupKey(lhs: lhs, left: left, right: right)
        guard !processed.contains(key) else { return }
        processed.insert(key)
        guard let elems = byKey[key] else { return }

        let parent = symNode(lhs: lhs, left: left, right: right)
        for elem in elems {
            let packed = SPPFNode<NodeLabel>.packed(
                label: elem.label, leftExtent: left, rightExtent: right, pivot: elem.pivot)
            graph.addEdge(from: parent, to: packed)

            // ── Left child ──────────────────────────────────────────────────
            // alpha = symbols consumed so far = symbols[0..<position]
            let alpha = Array(elem.label.symbols.prefix(elem.label.position))

            if elem.leftExtent < elem.pivot {
                if alpha.count == 1 {
                    // Single consumed symbol → attach directly (BUG 2 fix for single-sym completed).
                    addLeafOrSymbol(from: packed, symbol: alpha[0],
                                    left: elem.leftExtent, right: elem.pivot,
                                    tokens: tokens, graph: graph, byKey: byKey, populate: populate)
                } else if alpha.count > 1 {
                    // Multiple consumed symbols → intermediate node.
                    // BUG 3 fix: dot position = alpha.count − 1 (not label.position − 1).
                    let intLabel = NodeLabel(
                        goal: elem.label.goal,
                        symbols: elem.label.symbols,
                        position: alpha.count - 1)
                    let intNode = SPPFNode<NodeLabel>.intermediate(
                        label: intLabel, leftExtent: elem.leftExtent, rightExtent: elem.pivot)
                    graph.addEdge(from: packed, to: intNode)
                }
            }

            // ── Right child ─────────────────────────────────────────────────
            if elem.pivot < elem.rightExtent, let lastSym = alpha.last {
                addLeafOrSymbol(from: packed, symbol: lastSym,
                                left: elem.pivot, right: elem.rightExtent,
                                tokens: tokens, graph: graph, byKey: byKey, populate: populate)
            }
        }
    }

    populate(lhs: grammar.start, left: 0, right: n)
    graph.cleanup()
    return graph
}

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

private struct SPPFLookupKey: Hashable {
    let lhs: NonTerminal; let left, right: Int
}

private func addLeafOrSymbol(
    from parent: SPPFNode<NodeLabel>,
    symbol: Symbol,
    left: Int, right: Int,
    tokens: [String],
    graph: SPPFGraph<NodeLabel>,
    byKey: [SPPFLookupKey: [BSR<NodeLabel>]],
    populate: (NonTerminal, Int, Int) -> Void
) {
    switch symbol {
    case .terminal(let t):
        let tok: String
        if t.isEmpty {
            tok = MetaTerminal.eps.rawValue
        } else {
            tok = left < tokens.count ? tokens[left] : t.description
        }
        graph.addEdge(from: parent, to:
            SPPFNode<NodeLabel>.leaf(label: tok, leftExtent: left, rightExtent: right))
    case .nonTerminal(let nt):
        let child = SPPFNode<NodeLabel>.symbol(label: nt.name, leftExtent: left, rightExtent: right)
        graph.addEdge(from: parent, to: child)
        populate(nt, left, right)
    case .metaSymbol(let ms):
        graph.addEdge(from: parent, to:
            SPPFNode<NodeLabel>.leaf(label: ms.rawValue, leftExtent: left, rightExtent: right))
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

    /// When `true`, `parse(tokens:)` uses the extended-lookahead (EL)
    /// algorithm instead of the simple-lookahead (SL) algorithm.
    /// EL is strictly more precise for grammars with hidden left recursion.
    /// Default: `false`.
    public var useExtendedLookahead: Bool

    // MARK: - Init

    /// BUG 5 fix: always build both tables; algorithm is selected at call time.
    public init(grammar: Grammar, useExtendedLookahead: Bool = false) {
        self.grammar              = grammar
        self.nfa                  = buildEarleyNFA(grammar: grammar)
        self.slTable              = buildSLParseTable(nfa: nfa, grammar: grammar)
        self.elTable              = buildELParseTable(nfa: nfa, grammar: grammar)
        self.useExtendedLookahead = useExtendedLookahead
    }

    // MARK: - Core parse

    /// Run the parser on a pre-tokenised input and return an
    /// `EarleyTableParseResult` that exposes the BSR set, Earley sets, and
    /// (on success) the SPPF graph.
    ///
    /// BUG 6 fix: this method was previously declared but never implemented.
    ///
    /// - Parameter tokens: Pre-tokenised input as an array of terminal strings.
    /// - Returns: `EarleyTableParseResult` on acceptance.
    /// - Throws: `SyntaxError` if the input is not in the language.
    public func parse(tokens: [String]) throws -> EarleyTableParseResult {
        let raw: EarleyTableParseResult
        if useExtendedLookahead {
            raw = parseET(table: elTable, input: tokens)
        } else {
            raw = simpleET(table: slTable, input: tokens)
        }

        guard raw.accepted else {
            let joined = tokens.joined(separator: " ")
            throw SyntaxError(
                range: joined.startIndex..<joined.endIndex,
                in: joined,
                reason: .unexpectedToken)
        }

        let sppf = buildSPPF(from: raw.bsrSet, grammar: grammar, tokens: tokens)
        return EarleyTableParseResult(
            accepted:   raw.accepted,
            bsrSet:     raw.bsrSet,
            earleySets: raw.earleySets,
            sppfGraph:  sppf)
    }
}

// MARK: - DeterministicParser conformance

extension EarleyTableParser: DeterministicParser {

    /// Parse `string`, tokenised by whitespace, and return one parse tree.
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
        let parsed = try parseStream(stream)
        return ParseResult(
            isSuccessful: true,
            bsr: parsed.result.bsrSet,
            sppfGraph: parsed.result.sppfGraph)
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

// MARK: - Tokenisation and range-mapping helpers

extension EarleyTableParser {

    private func parseStream<S: TokenStream>(
        _ stream: S
    ) throws -> (result: EarleyTableParseResult, ranges: [Range<String.Index>]) {
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
        return (try parse(tokens: tokens), ranges)
    }

    @available(*, deprecated, message: "Use parse(stream:) with a TokenStream")
    /// Split `string` on whitespace (omitting empty subsequences).
    func tokenize(_ string: String) -> [String] {
        string.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    /// Build a per-token `Range<String.Index>` array by scanning `string`
    /// for each whitespace-separated token in order.
    ///
    /// Required by SPPFGraph.buildParseTree / buildAllParseTrees (Parser module
    /// TreeBuilder extension): they map token-index extents back to source ranges.
    func tokenRanges(for tokens: [String], in string: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        ranges.reserveCapacity(tokens.count)
        var search = string.startIndex

        for token in tokens {
            guard let range = string.range(of: token, range: search..<string.endIndex) else {
                // Shouldn't happen if `tokens` came from `tokenize(string)`.
                let idx = search
                ranges.append(idx..<idx)
                continue
            }
            ranges.append(range)
            search = range.upperBound
        }
        return ranges
    }
}
