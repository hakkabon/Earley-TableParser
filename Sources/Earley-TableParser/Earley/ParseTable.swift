// ParseTable.swift
// Defines Binary Subtree Representation (BSR) elements and builds the
// SL parse table  𝒯_Γ^SL  used by simpleET() in Section 7.1.
//
// A BSR element  (Ω, i, k, j)  represents a binarised derivation subtree:
//   Ω  is either a production rule or a string that is a left prefix of a rhs
//   i  is the left extent (start input position)
//   k  is the pivot (split point)
//   j  is the right extent (end input position)
//
// The SL table entry is a 4-tuple:
//   𝒯_Γ^SL(p, x) = (m, A_{p,x}, m(G_p, x), em(G_p, x))
// where
//   m         = next NFA state (or ⊥)
//   A_{p,x}   = completer set (same as in recogniser table)
//   χ₁ = m(G_p, x)  = set of BSR grammar components for terminal/NT transitions
//   χ₂ = em(G_p, x) = set of BSR components for ε-related nullable matches

import Foundation

// MARK: - BSR Grammar Component (Ω)

/// The grammar component of a BSR element.
/// Either a complete production rule or a left-prefix string of length ≥ 2.
public enum BSRComponent: Hashable, CustomStringConvertible {
    /// A complete production  X ::= γ  (used when the right child is a terminal or ε).
    case production(Production)
    /// A left prefix  δx  of some production rhs, length ≥ 2.
    /// Stored as (lhs, prefix) for display; the pivot structure
    /// is determined by the BSR element's indices.
    case prefix(lhs: String, symbols: [Symbol])

    public var description: String {
        switch self {
        case .production(let p):
            return p.description
        case .prefix(let lhs, let syms):
            return "\(lhs) ::= \(syms.map(\.description).joined(separator: " "))"
        }
    }
}

// MARK: - BSR Element

/// A BSR element  (Ω, i, k, j).
public struct BSRElement: Hashable, CustomStringConvertible {
    public let omega:      BSRComponent
    public let leftExtent: Int   // i
    public let pivot:      Int   // k
    public let rightExtent: Int  // j

    public var description: String {
        "(\(omega), \(leftExtent), \(pivot), \(rightExtent))"
    }
}

// MARK: - m() and em() pre-computed sets

/// m(M, x): BSR grammar components generated when transitioning on symbol x ≠ ε.
/// From Section 6.4:
///   m(M, x) = { Y ::= γx | (Y ::= γ·x) ∈ M }
///           ∪ { δx   | (Y ::= δ·xτ) ∈ M, δ ≠ ε, τ ≠ ε }
///   m(M, ε) = ∅
func mSets(_ M: Set<Slot>, symbol x: Symbol) -> Set<BSRComponent> {
    guard case .epsilon = x else {
        // x ≠ ε
        var result = Set<BSRComponent>()
        for slot in M {
            guard let next = slot.nextSymbol, next == x else { continue }
            let prefix = slot.production.rhs[..<slot.dot]
            let newRhs  = Array(slot.production.rhs[..<(slot.dot + 1)])

            if slot.dot + 1 == slot.production.rhs.count {
                // Y ::= γx  (the full production up to and including x)
                // Use production component.
                result.insert(.production(slot.production))
            } else {
                // δx is a proper prefix (length ≥ 2 if delta non-empty, otherwise length 1)
                // The paper requires |γω| ≥ 1 effectively, capturing the left prefix.
                if newRhs.count >= 2 || (newRhs.count == 1 && !prefix.isEmpty) {
                    result.insert(.prefix(lhs: slot.production.lhs, symbols: newRhs))
                } else {
                    // single-symbol prefix — still record
                    result.insert(.prefix(lhs: slot.production.lhs, symbols: newRhs))
                }
            }
        }
        return result
    }
    return []
}

/// em(M, x): the ε-related BSR component set.
/// From Section 6.5 / page 14:
///   em(move(M,x)) captures nullable-ω contributions.
///   For non-ε x and the result state G_j = move(M, x):
///   em(G_j) = e(move(M,x))  if x ∈ N_Γ ∪ T_Γ and G_j is not core
///           = e(move(M,x))  if x = ε  (but we handle ε separately)
/// We use the definition:
///   e(M) = { Y ::= γω | (Y ::= γ·ω) ∈ M }
///         ∪ { γω     | (Y ::= δ·ωτ) ∈ M,  δ,τ ≠ ε }
/// where ω is nullable.
func eSets(_ M: Set<Slot>, grammar: Grammar) -> Set<BSRComponent> {
    var result = Set<BSRComponent>()
    for slot in M {
        guard let next = slot.nextSymbol else { continue }
        // Only include if the symbol after the dot is nullable (ω ⟹* ε)
        let isNullableNext: Bool
        switch next {
        case .nonterminal(let n): isNullableNext = grammar.isNullableNonterminal(n)
        case .epsilon:            isNullableNext = true
        case .terminal:           isNullableNext = false
        }
        guard isNullableNext else { continue }

        let prefix = Array(slot.production.rhs[..<slot.dot])
        if !prefix.isEmpty {
            // γω where γ ≠ ε — prefix component
            result.insert(.prefix(lhs: slot.production.lhs, symbols: prefix))
        } else {
            // γ is empty — production component (ω is the whole rhs)
            result.insert(.production(slot.production))
        }
    }
    return result
}

// MARK: - SL Parse Table Entry

public struct SLTableEntry {
    /// Next NFA state index (nil = ⊥).
    public let nextState:      Int?
    /// Completer set A_{p,x}.
    public let completedNTs:   Set<String>
    /// χ₁ = m(G_p, x): BSR components for direct matches.
    public let chi1:           Set<BSRComponent>
    /// χ₂ = em(G_p, x): BSR components for nullable matches.
    public let chi2:           Set<BSRComponent>
}

// MARK: - SL Parse Table

public struct SLParseTable {
    let entries: [[String: SLTableEntry]]  // [state][symbolName]
    public let nfa: EarleyNFA
    public let grammar: Grammar

    public func entry(state p: Int, symbol x: String) -> SLTableEntry? {
        guard p < entries.count else { return nil }
        return entries[p][x]
    }
}

// MARK: - Table Builder

public func buildSLParseTable(nfa: EarleyNFA, grammar: Grammar) -> SLParseTable {
    let follow = grammar.followSets()
    let termSymbols:    [String] = Array(grammar.terminals) + ["$"]
    let nontermSymbols: [String] = Array(grammar.nonterminals)

    var entries = [[String: SLTableEntry]](repeating: [:], count: nfa.stateCount)

    for p in 0..<nfa.stateCount {
        let gp = nfa.states[p]

        // Pre-compute m() and em() for all symbols.
        for t in termSymbols {
            let sym  = Symbol.terminal(t)
            let next = nfa.transition(from: p, on: sym)

            var completed = Set<String>()
            for slot in gp where slot.isComplete {
                if follow[slot.production.lhs]?.contains(t) == true {
                    completed.insert(slot.production.lhs)
                }
            }

            let chi1 = mSets(gp, symbol: sym)
            // χ₂: em of the target state (if it exists)
            let chi2: Set<BSRComponent>
            if let h = next {
                let gm = nfa.states[h]
                chi2 = eSets(gm, grammar: grammar)
            } else {
                chi2 = []
            }

            entries[p][t] = SLTableEntry(
                nextState: next, completedNTs: completed, chi1: chi1, chi2: chi2)
        }

        for nt in nontermSymbols {
            let sym  = Symbol.nonterminal(nt)
            let next = nfa.transition(from: p, on: sym)

            let chi1 = mSets(gp, symbol: sym)
            let chi2: Set<BSRComponent>
            if let h = next {
                let gm = nfa.states[h]
                chi2 = eSets(gm, grammar: grammar)
            } else {
                chi2 = []
            }

            entries[p][nt] = SLTableEntry(
                nextState: next, completedNTs: [], chi1: chi1, chi2: chi2)
        }

        // ε column
        let epsNext = nfa.transition(from: p, on: .epsilon)
        entries[p]["ε"] = SLTableEntry(
            nextState: epsNext, completedNTs: [], chi1: [], chi2: [])
    }

    return SLParseTable(entries: entries, nfa: nfa, grammar: grammar)
}
