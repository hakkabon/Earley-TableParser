// EarleyParser.swift
// Implements simpleET() from Section 7.1 of Scott & Johnstone (2026).
//
// simpleET() extends recET() by building the BSR set Υ alongside the
// Earley sets.  ADD() is enriched to also populate Υ with BSR elements
// derived from χ₁ and χ₂.
//
// The BSR set Υ represents the full set of derivations (packed as
// binarised subtrees) and can later be walked to produce SPPF graphs
// or individual syntax trees.
//
// Grammar library API:
//   production.goal  : NonTerminal
//   production.rule  : [Symbol]
//   grammar.start    : NonTerminal

import Foundation
import Grammar


/// Heuristic ambiguity check on the raw BSR set:
/// if two distinct BSR elements share the same (LHS, leftExtent, rightExtent)
/// the parse is ambiguous.
func bsrSetIsAmbiguous(_ bsr: Set<BSRElement>) -> Bool {
    var seen = Set<AmbiguityKey>()
    for elem in bsr {
        guard let lhs = elem.omega.lhsNonterminal else { continue }
        let key = AmbiguityKey(lhs: lhs, left: elem.leftExtent, right: elem.rightExtent)
        if !seen.insert(key).inserted { return true }
    }
    return false
}

private struct AmbiguityKey: Hashable {
    let lhs: NonTerminal
    let left, right: Int
}

// MARK: - simpleET()

/// The simple-lookahead Earley Table Traversing Parser (Section 7.1.1).
///
/// Takes a pre-built SL parse table and a tokenised input, and returns
/// an `EarleyParseResult` containing:
///   - acceptance flag
///   - the BSR set Υ
///   - the Earley sets 𝔼₀ … 𝔼_n
public func simpleET(table: SLParseTable, input tokens: [String]) -> ParseResult {
    let n = tokens.count

    // a(j) = tokens[j-1] for j in 1…n;  a(n+1) = "$"
    func a(_ j: Int) -> String {
        j >= 1 && j <= n ? tokens[j - 1] : eofKey
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)
    var Upsilon = Set<BSRElement>()

    /// ADD(p, x, i, k, j) from Figure 7.1:
    ///   p — current NFA state
    ///   x — symbol key being consumed
    ///   i — back-index (origin of the last ε-transition)
    ///   k — pivot (input position active when state p was entered)
    ///   j — target input position
    @discardableResult
    func add(state p: Int, symbol x: String, backIndex i: Int, pivot k: Int, position j: Int) -> Bool {
        guard let entry = table.entry(state: p, symbol: x) else { return false }

        // Populate BSR set from χ₁: (Ω, i, k, j)
        for omega in entry.chi1 {
            Upsilon.insert(BSRElement(omega: omega, leftExtent: i, pivot: k, rightExtent: j))
        }

        // Populate BSR set from χ₂: (Ω, i, j, j)   (ε-pivot = j)
        for omega in entry.chi2 {
            Upsilon.insert(BSRElement(omega: omega, leftExtent: i, pivot: j, rightExtent: j))
        }

        // Update Earley set 𝔼_j.
        guard let h = entry.nextState else { return false }
        let pair = EarleyPair(state: h, backIndex: i)
        if E[j].insert(pair).inserted {
            R[j].append(pair)
            return true
        }
        return false
    }

    // Initialise 𝔼₀ = R₀ = { (0, 0) }
    E[0].insert(EarleyPair(state: 0, backIndex: 0))
    R[0].append(EarleyPair(state: 0, backIndex: 0))

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple

            // (i) Completer: k ≠ j
            if k != j {
                let nextTok = a(j + 1)
                // Completers are stored under the terminal key of the lookahead.
                for nt in table.entry(state: p, symbol: nextTok)?.completedNTs ?? [] {
                    let ntKey = nonTerminalKey(nt)
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: ntKey, backIndex: i, pivot: k, position: j)
                    }
                }
            }

            // (ii) ε-transition: ADD(p, ε, j, j, j)
            add(state: p, symbol: epsilonKey, backIndex: j, pivot: j, position: j)

            // (iii) Scanner: ADD(p, a_{j+1}, k, j, j+1)
            if j < n {
                add(state: p, symbol: a(j + 1), backIndex: k, pivot: j, position: j + 1)
            }
        }
    }

    // Acceptance check: some (p, 0) ∈ 𝔼_n where G_p contains a complete start item.
    let startNT = nfa_startNonterminal(nfa: table.nfa) ?? table.grammar.start
    let accepted = E[n].contains { pair in
        pair.backIndex == 0 &&
        table.nfa.states[pair.state].contains { slot in
            slot.isComplete && slot.production.goal == startNT
        }
    }

    return ParseResult(accepted: accepted, bsrSet: Upsilon, earleySets: E, sppfGraph: nil)
}

// MARK: - BSR → SPPF construction

/// Build an SPPF graph from a BSR set.
///
/// The construction follows the structure of the BSR elements:
///   • Each complete `.production` element becomes a symbol node.
///   • Each `.prefix` element becomes an intermediate node.
///   • Ambiguity is represented by packed nodes below a shared parent.
public func buildSPPF(from bsrSet: Set<BSRElement>, grammar: Grammar, tokens: [String]) -> SPPFGraph {
    let graph = SPPFGraph()
    let n = tokens.count

    // Index BSR elements for quick lookup:  (lhsName, leftExtent, rightExtent) → [BSRElement]
    var byLHSAndExtents: [SPPFLookupKey: [BSRElement]] = [:]
    for elem in bsrSet {
        guard let lhs = elem.omega.lhsNonterminal else { continue }
        let key = SPPFLookupKey(lhs: lhs, left: elem.leftExtent, right: elem.rightExtent)
        byLHSAndExtents[key, default: []].append(elem)
    }

    // Create or find the symbol node for (lhs, i, j).
    func getOrMakeSymbolNode(lhs: NonTerminal, left: Int, right: Int) -> GraphNode {
        let node = GraphNode.symbol(label: lhs.name, leftExtent: left, rightExtent: right)
        graph.add(node)
        return node
    }

    // Recursively add packed children for each BSR element that derives (lhs, i, j).
    func populate(lhs: NonTerminal, left: Int, right: Int) {
        let key = SPPFLookupKey(lhs: lhs, left: left, right: right)
        guard let elems = byLHSAndExtents[key] else { return }
        let parent = getOrMakeSymbolNode(lhs: lhs, left: left, right: right)

        for elem in elems {
            // Create a packed node for this particular BSR element.
            let nodeLabel = NodeLabel(
                goal: lhs,
                symbols: bsrComponentSymbols(elem.omega),
                position: bsrComponentDotPosition(elem.omega))
            let packed = GraphNode.packed(label: nodeLabel, pivot: elem.pivot)
            graph.addEdge(from: parent, to: packed)

            // Left child: whatever spans (left…pivot).
            addLeftChild(of: packed, elem: elem, tokens: tokens, graph: graph,
                         byLHSAndExtents: byLHSAndExtents, populate: populate)

            // Right child: whatever spans (pivot…right).
            addRightChild(of: packed, elem: elem, tokens: tokens, graph: graph,
                          byLHSAndExtents: byLHSAndExtents, populate: populate)
        }
    }

    // Start from the root: (start, 0, n).
    let rootNT = grammar.start
    populate(lhs: rootNT, left: 0, right: n)

    return graph
}

private struct SPPFLookupKey: Hashable {
    let lhs: NonTerminal; let left, right: Int
}

/// Symbols in the BSR component (used as the NodeLabel's symbol array).
private func bsrComponentSymbols(_ omega: BSRComponent) -> [Symbol] {
    switch omega {
    case .production(let p): return p.rule
    case .prefix(_, let syms): return syms
    }
}

/// The dot position in a BSR component (all symbols have been consumed).
private func bsrComponentDotPosition(_ omega: BSRComponent) -> Int {
    switch omega {
    case .production(let p): return p.rule.count
    case .prefix(_, let syms): return syms.count
    }
}

private func addLeftChild(
    of packed: GraphNode,
    elem: BSRElement,
    tokens: [String],
    graph: SPPFGraph,
    byLHSAndExtents: [SPPFLookupKey: [BSRElement]],
    populate: (NonTerminal, Int, Int) -> Void
) {
    guard elem.leftExtent < elem.pivot else { return }
    switch elem.omega {
    case .prefix(let lhs, let syms):
        // The left child is an intermediate node covering [left…pivot].
        let label = NodeLabel(goal: lhs, symbols: syms, position: syms.count - 1)
        let intermediate = GraphNode.intermediate(
            label: label, leftExtent: elem.leftExtent, rightExtent: elem.pivot)
        graph.addEdge(from: packed, to: intermediate)
    case .production(let prod):
        // Single-symbol production — left child is a leaf or symbol node.
        if prod.rule.count == 1 {
            addLeafOrSymbol(from: packed, symbol: prod.rule[0],
                            left: elem.leftExtent, right: elem.pivot,
                            tokens: tokens, graph: graph,
                            byLHSAndExtents: byLHSAndExtents, populate: populate)
        }
    }
}

private func addRightChild(
    of packed: GraphNode,
    elem: BSRElement,
    tokens: [String],
    graph: SPPFGraph,
    byLHSAndExtents: [SPPFLookupKey: [BSRElement]],
    populate: (NonTerminal, Int, Int) -> Void
) {
    guard elem.pivot < elem.rightExtent else { return }
    let syms = bsrComponentSymbols(elem.omega)
    guard let lastSym = syms.last else { return }

    addLeafOrSymbol(from: packed, symbol: lastSym,
                    left: elem.pivot, right: elem.rightExtent,
                    tokens: tokens, graph: graph,
                    byLHSAndExtents: byLHSAndExtents, populate: populate)
}

private func addLeafOrSymbol(
    from parent: GraphNode,
    symbol: Symbol,
    left: Int, right: Int,
    tokens: [String],
    graph: SPPFGraph,
    byLHSAndExtents: [SPPFLookupKey: [BSRElement]],
    populate: (NonTerminal, Int, Int) -> Void
) {
    switch symbol {
    case .terminal:
        let tok = left < tokens.count ? tokens[left] : ""
        let leaf = GraphNode.leaf(label: tok, leftExtent: left, rightExtent: right)
        graph.addEdge(from: parent, to: leaf)
    case .nonTerminal(let nt):
        let symNode = GraphNode.symbol(label: nt.name, leftExtent: left, rightExtent: right)
        graph.addEdge(from: parent, to: symNode)
        populate(nt, left, right)
    case .metaSymbol:
        break
    }
}

// MARK: - Derivation extraction

/// Extract a single derivation tree from a BSR set as a readable string.
/// Useful for debugging and unit tests on unambiguous inputs.
public func extractDerivation(
    from bsrSet: Set<BSRElement>,
    grammar: Grammar,
    tokens: [String]
) -> String? {
    let start = grammar.start
    let n = tokens.count

    guard let root = bsrSet.first(where: { elem in
        elem.leftExtent == 0 &&
        elem.rightExtent == n &&
        elem.omega.lhsNonterminal == start
    }) else { return nil }

    return walkBSR(elem: root, bsrSet: bsrSet, tokens: tokens)
}

private func walkBSR(elem: BSRElement, bsrSet: Set<BSRElement>, tokens: [String]) -> String {
    switch elem.omega {
    case .production(let prod):
        if prod.rule.isEmpty { return "(\(prod.goal.name) → ε)" }
        let children = reconstructChildren(
            prod: prod, left: elem.leftExtent, pivot: elem.pivot, right: elem.rightExtent,
            bsrSet: bsrSet, tokens: tokens)
        return "(\(prod.goal.name) → \(children.joined(separator: " ")))"
    case .prefix(let lhs, let syms):
        return "(\(lhs.name)/prefix[\(syms.map(\.description).joined())] \(elem.leftExtent),\(elem.pivot),\(elem.rightExtent))"
    }
}

private func reconstructChildren(
    prod: Production,
    left i: Int, pivot k: Int, right j: Int,
    bsrSet: Set<BSRElement>,
    tokens: [String]
) -> [String] {
    guard !prod.rule.isEmpty else { return ["ε"] }

    if prod.rule.count == 1 {
        switch prod.rule[0] {
        case .terminal:
            return [i < tokens.count ? "'\(tokens[i])'" : "'?'"]
        case .nonTerminal(let nt):
            if let child = bsrSet.first(where: {
                $0.leftExtent == i && $0.rightExtent == j &&
                $0.omega.lhsNonterminal == nt
            }) {
                return [walkBSR(elem: child, bsrSet: bsrSet, tokens: tokens)]
            }
            return ["(\(nt.name) [\(i),\(j)])"]
        case .metaSymbol:
            return ["ε"]
        }
    }
    // For multi-symbol productions, show the extents.
    return ["[\(i)…\(j) via \(k)]"]
}
