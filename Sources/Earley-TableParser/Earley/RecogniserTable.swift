// RecogniserTable.swift
// Builds the recogniser table  𝒯_Γ  and implements the  recET()  algorithm
// from Section 5 of Scott & Johnstone (2025).
//
// Table entry  𝒯_Γ(p, x) = (m, A)  where
//   m  is the target NFA state index (or ⊥ = nil) after transitioning on x
//   A  is the set of nonterminals Y such that G_p contains Y ::= γ·
//      and x ∈ FOLLOW(Y)  — the SLR(1)-style lookahead set for completers.

import Foundation
import Grammar

// MARK: - Recogniser Table Entry

public struct RecTableEntry {
    /// Target state after consuming x (nil = dead / ⊥).
    public let nextState: Int?
    /// Nonterminals completed at this state whose FOLLOW contains x.
    /// Used by recET() completer action.
    public let completedNTs: Set<String>
}

// MARK: - Recogniser Table  𝒯_Γ

/// The pre-computed recogniser table.
/// `table[p][x]` gives the entry for state p and symbol-string x.
public struct RecogniserTable {
    let entries: [[String: RecTableEntry]]  // indexed by state, keyed by symbol name
    let nfa: EarleyNFA

    public var stateCount: Int { entries.count }

    /// Look up entry for state p and terminal/nonterminal name x.
    public func entry(state p: Int, symbol x: String) -> RecTableEntry? {
        guard p < entries.count else { return nil }
        return entries[p][x]
    }

    /// The set A_{p, x}: nonterminals completed at p with x in FOLLOW.
    public func completers(state p: Int, symbol x: String) -> Set<String> {
        entry(state: p, symbol: x)?.completedNTs ?? []
    }

    /// Next state from p on symbol x (nil = ⊥).
    public func nextState(from p: Int, symbol x: String) -> Int? {
        entry(state: p, symbol: x)?.nextState ?? nil
    }
}

// MARK: - Table Builder

public func buildRecogniserTable(nfa: EarleyNFA, grammar: Grammar) -> RecogniserTable {
    let follow = grammar.followSets()

    var entries = [[String: RecTableEntry]](
        repeating: [:],
        count: nfa.stateCount
    )

    // All terminal names + "$" (end of input sentinel).
    let termSymbols: [String] = Array(grammar.terminals) + ["$"]
    // All nonterminal names.
    let nontermSymbols: [String] = Array(grammar.nonTerminals)

    for p in 0..<nfa.stateCount {
        // --- Terminal columns (and $) ---
        for t in termSymbols {
            let sym = Symbol.terminal(t)
            let next = nfa.transition(from: p, on: sym)

            // A = { Y | Y ::= γ· ∈ G_p  and  t ∈ FOLLOW(Y) }
            var completed = Set<String>()
            for slot in nfa.states[p] where slot.isComplete {
                let y = slot.production.lhs
                if follow[y]?.contains(t) == true { completed.insert(y) }
            }
            entries[p][t] = RecTableEntry(nextState: next, completedNTs: completed)
        }

        // --- Nonterminal columns ---
        for nt in nontermSymbols {
//            let sym = Symbol.nonTerminal(nt)
            if case .nonTerminal(let nt) = nt {
                let next = nfa.transition(from: p, on: nt)
                // No completer set needed for nonterminal columns in recET
                // (completions are indexed by terminals).
                entries[p][nt] = RecTableEntry(nextState: next, completedNTs: [])
            }
        }

        // --- ε column ---
        let epsNext = nfa.transition(from: p, on: .epsilon)
        entries[p]["ε"] = RecTableEntry(nextState: epsNext, completedNTs: [])
    }

    return RecogniserTable(entries: entries, nfa: nfa)
}

// MARK: - recET() Recogniser

/// The Earley recogniser table traverser from Section 5.2.
///
/// Sets 𝔼_j contain pairs (p, k):
///   p = current NFA state
///   k = back-index (input position where the most recent ε-transition occurred)
///
/// Returns true iff the input is in the language of the grammar.
public func recET(table: RecogniserTable, input tokens: [String]) -> Bool {
    let n = tokens.count
    let grammar_startNT = table.nfa.states[0]
        .filter { $0.dot == 0 }
        .map    { $0.production.goal }
        .first ?? ""

    // E[j] = set of (state, back-index) pairs
    // R[j] = worklist for E[j]
    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)

    // a[j] for j in 1...n is tokens[j-1]; a[n+1] = "$"
    func a(_ j: Int) -> String {
        if j <= n { return tokens[j - 1] }
        return "$"
    }

    /// ADD(p, x, i, j): attempt transition from state p on symbol x with
    /// back-index i, adding to 𝔼_j / R_j.
    func add(state p: Int, symbol x: String, backIndex i: Int, position j: Int) {
        guard let entry = table.entry(state: p, symbol: x),
              let h = entry.nextState,
              h != -1 else { return }
        let pair = EarleyPair(state: h, backIndex: i)
        if E[j].insert(pair).inserted {
            R[j].append(pair)
        }
    }

    // Initialise: E₀ = R₀ = { (0, 0) }
    let init0 = EarleyPair(state: 0, backIndex: 0)
    E[0].insert(init0)
    R[0].append(init0)

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple

            // (8) Completer action: k ≠ j
            if k != j {
                // For each X ∈ A_{p, a_{j+1}}:  for each (h, i) ∈ 𝔼_k: ADD(h, X, i, j)
                let nextToken = a(j + 1)
                let completedXs = table.completers(state: p, symbol: nextToken)
                for x in completedXs {
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: x, backIndex: i, position: j)
                    }
                }
            }

            // (11) ε-transition: ADD(p, ε, j, j)
            add(state: p, symbol: "ε", backIndex: j, position: j)

            // (12) Scanner: if j < n, ADD(p, a_{j+1}, k, j+1)
            if j < n {
                add(state: p, symbol: a(j + 1), backIndex: k, position: j + 1)
            }
        }
    }

    // Accept if some (p, 0) ∈ 𝔼_n where G_p is an accepting state.
    // G_p is accepting if it contains S ::= γ· (complete item for start symbol).
    return E[n].contains(where: { pair in
        pair.backIndex == 0 &&
        table.nfa.states[pair.state].contains(where: { slot in
            slot.isComplete && slot.production.goal == grammar_startNT
        })
    })
}

// MARK: - Helper

public struct EarleyPair: Hashable {
    public let state:     Int
    public let backIndex: Int

    var asTuple: (Int, Int) { (state, backIndex) }
}
