// Parser.swift
// Implements simpleET() from Section 7.1 of Scott & Johnstone (2025).
//
// simpleET() extends recET() by building a BSR set Υ alongside the
// Earley sets.  The only change from recET() is an enriched ADD()
// which also populates Υ with BSR elements derived from χ₁ and χ₂.
//
// The BSR set Υ represents the full set of derivations of the input
// (packed as binarised subtrees) and can later be walked to extract
// individual parse trees or construct an SPPF.

import Foundation
import Grammar

// MARK: - Parser Result

public struct EarleyParseResult {
    /// Whether the input is in the language.
    public let accepted: Bool
    /// The BSR set Υ representing all parse derivations.
    public let bsrSet:   Set<BSRElement>
    /// The Earley sets 𝔼_j (each contains (state, backIndex) pairs).
    public let earleySets: [Set<EarleyPair>]
    /// The SPPF graph constructed from BSR elements.
    public let sppfGraph: SPPFGraph?
    
    public var hasAmbiguity: Bool {
        guard let graph = sppfGraph else { return false }
        return graph.getAllNodes().contains { node in
            graph.getChildren(of: node).count > 1
        }
    }
}

// MARK: - simpleET()

/// The simple lookahead Earley table parser (Section 7.1.1).
///
/// Takes an SL parse table and a token sequence and returns a EarleyParseResult
/// containing the BSR set Υ and the Earley sets.
public func simpleET(table: SLParseTable, input tokens: [String]) -> EarleyParseResult {
    let n = tokens.count

    // a[j] for j in 1...n is tokens[j-1]; a[n+1] = "$"
    func a(_ j: Int) -> String {
        if j >= 1 && j <= n { return tokens[j - 1] }
        return "$"
    }

    // 𝔼_j sets and worklists R_j
    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)

    // Global BSR set Υ (updated by ADD).
    var Upsilon = Set<BSRElement>()

    /// ADD(p, x, i, k, j) from Section 7.1.1.
    /// - p:  current state
    /// - x:  symbol being matched (terminal name, NT name, or "ε")
    /// - i:  back-index (position of last ε-transition)
    /// - k:  pivot (current input position when p was active)
    /// - j:  target input position
    @discardableResult
    func add(state p: Int, symbol x: String, backIndex i: Int, pivot k: Int, position j: Int) -> Bool {
        guard let entry = table.entry(state: p, symbol: x) else { return false }

        // Add BSR elements from χ₁: each Ω in χ₁ → (Ω, i, k, j)
        for omega in entry.chi1 {
            Upsilon.insert(BSRElement(omega: omega, leftExtent: i, pivot: k, rightExtent: j))
        }

        // Add BSR elements from χ₂: each Ω in χ₂ → (Ω, i, j, j)
        for omega in entry.chi2 {
            Upsilon.insert(BSRElement(omega: omega, leftExtent: i, pivot: j, rightExtent: j))
        }

        // Update Earley sets.
        guard let h = entry.nextState else { return false }
        let pair = EarleyPair(state: h, backIndex: i)
        if E[j].insert(pair).inserted {
            R[j].append(pair)
            return true
        }
        return false
    }

    // Initialise: 𝔼₀ = R₀ = {(0, 0)}
    let init0 = EarleyPair(state: 0, backIndex: 0)
    E[0].insert(init0)
    R[0].append(init0)

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple

            // (completer) k ≠ j
            if k != j {
                let nextToken = a(j + 1)
                let completedXs = table.entry(state: p, symbol: nextToken)?.completedNTs ?? []
                for x in completedXs {
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: x, backIndex: i, pivot: k, position: j)
                    }
                }
            }

            // ε-transition: ADD(p, ε, j, j, j)
            add(state: p, symbol: "ε", backIndex: j, pivot: j, position: j)

            // scanner: if j < n, ADD(p, a_{j+1}, k, j, j+1)
            if j < n {
                add(state: p, symbol: a(j + 1), backIndex: k, pivot: j, position: j + 1)
            }
        }
    }

    // Determine start nonterminal (lhs of a complete item reachable from state 0).
    let startNT = table.nfa.states[0]
        .compactMap { $0.dot == 0 ? $0.production.lhs : nil }
        .first ?? ""

    let accepted = E[n].contains(where: { pair in
        pair.backIndex == 0 &&
        table.nfa.states[pair.state].contains(where: { slot in
            slot.isComplete && slot.production.lhs == startNT
        })
    })

    return EarleyParseResult(accepted: accepted, bsrSet: Upsilon, earleySets: E, sppfGraph: nil)
}

// MARK: - BSR Walker (derivation extraction)

/// Extracts one derivation tree from a BSR set as a nested string representation.
/// This is a simple recursive descent over the BSR elements.
public func extractDerivation(
    from bsrSet: Set<BSRElement>,
    grammar: Grammar,
    input tokens: [String],
    startSymbol: String? = nil
) -> String? {
    let start = startSymbol ?? grammar.startSymbol
    let n = tokens.count

    // Find the root BSR element: production for start with extents (0, ?, n)
    guard let root = bsrSet.first(where: { elem in
        elem.leftExtent == 0 && elem.rightExtent == n &&
        (elem.omega.lhsName == start)
    }) else { return nil }

    return walkBSR(elem: root, bsrSet: bsrSet, tokens: tokens)
}

private func walkBSR(elem: BSRElement, bsrSet: Set<BSRElement>, tokens: [String]) -> String {
    switch elem.omega {
    case .production(let prod):
        let lhs = prod.lhs
        if prod.rhs.isEmpty {
            return "(\(lhs) → ε)"
        }
        // Try to reconstruct children.
        let children = reconstructChildren(
            prod: prod, leftExtent: elem.leftExtent,
            pivot: elem.pivot, rightExtent: elem.rightExtent,
            bsrSet: bsrSet, tokens: tokens)
        return "(\(lhs) → \(children.joined(separator: " ")))"

    case .prefix(let lhs, let syms):
        return "(\(lhs)/\(syms.map(\.description).joined()) [\(elem.leftExtent),\(elem.pivot),\(elem.rightExtent)])"
    }
}

private func reconstructChildren(
    prod: Production,
    leftExtent i: Int,
    pivot k: Int,
    rightExtent j: Int,
    bsrSet: Set<BSRElement>,
    tokens: [String]
) -> [String] {
    var result: [String] = []
    // Simple case: single-symbol rhs.
    if prod.rhs.count == 1 {
        switch prod.rhs[0] {
        case .terminal(let t):
            if i < tokens.count { result.append("'\(tokens[i])'") }
            else { result.append("'\(t)'") }
        case .nonterminal(let nt):
            if let child = bsrSet.first(where: {
                $0.leftExtent == i && $0.rightExtent == j &&
                $0.omega.lhsName == nt
            }) {
                result.append(walkBSR(elem: child, bsrSet: bsrSet, tokens: tokens))
            } else {
                result.append("(\(nt) [?\(i),\(j)])")
            }
        case .epsilon:
            result.append("ε")
        }
        return result
    }
    // Multi-symbol: report extents.
    result.append("[\(i)…\(j) via pivot \(k)]")
    return result
}

extension BSRComponent {
    var lhsName: String? {
        switch self {
        case .production(let p): return p.lhs
        case .prefix(let lhs, _): return lhs
        }
    }
}
