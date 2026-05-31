// EarleyNFA.swift
// Constructs the Earley NFA (Γ_NFA) from a grammar by computing
// calls(M) and move(M, x) as defined in Section 4.2 of the paper.
//
// The key ideas:
//   calls(M)   = smallest set of slots containing all the "left null call" slots
//                reachable from M via nonterminal calls and nullable transitions.
//   move(M, x) = the set of slots reached by matching symbol x from M,
//                closing over nullable nonterminals.
//
// NFA states are sets of slots (= Earley-entailment-closed sets).
// States are indexed G₀, G₁, … G_q once enumerated.

import Foundation

// MARK: - Entailment & calls()

/// Compute calls(M): the smallest superset of M satisfying:
///   (i)  If (X ::= α · Y δ) ∈ M  then  Y_LNcall ⊆ calls(M)
///   (ii) If (U ::= τ · V v) ∈ calls(M)  then  V_LNcall ⊆ calls(M)
/// where Y_LNcall = { X ::= ω·γ | X ::= ωγ ∈ P_Γ, ω ⟹* ε }
///
/// This implements Section 4.2 Definition (calls).
func calls(_ M: Set<Slot>, grammar: Grammar) -> Set<Slot> {
    // Build LNcall sets for all nonterminals on first use.
    // LNcall(X) = all slots  X ::= ω·γ  where  ω ⟹* ε
    func lnCallSlots(for name: String) -> Set<Slot> {
        var result = Set<Slot>()
        for prod in grammar.productions where prod.lhs == name {
            // Walk dot positions: add slot X ::= ω·γ when all of ω is nullable.
            for dot in 0...prod.rhs.count {
                let prefix = Array(prod.rhs[..<dot])
                if grammar.isNullable(prefix) {
                    result.insert(Slot(production: prod, dot: dot))
                } else {
                    break  // once a symbol is non-nullable the rest won't be either
                }
            }
        }
        return result
    }

    var result = M
    var worklist = Array(M)

    while let slot = worklist.popLast() {
        // For each slot with a nonterminal after the dot, add its LNcall slots.
        guard let next = slot.nextSymbol,
              case .nonterminal(let name) = next else { continue }

        for newSlot in lnCallSlots(for: name) {
            if result.insert(newSlot).inserted {
                worklist.append(newSlot)
            }
        }
    }
    return result
}

/// Compute move(M, x): slots reachable by consuming symbol x from state M.
///   move(M, x) = { X ::= γxω·δ | (X ::= γxω·δ) ∈ M, ω ⟹* ε }  ∪ calls of those slots
///   move(M, ε) = calls(M)  if M is core, else ∅
///
/// "core" = M is non-empty and does not contain any slot of the form X ::= ·γ
func move(_ M: Set<Slot>, symbol x: Symbol, grammar: Grammar) -> Set<Slot> {
    if case .epsilon = x {
        let isCore = !M.isEmpty && !M.contains(where: { $0.dot == 0 })
        return isCore ? calls(M, grammar: grammar) : []
    }

    // Collect advanced slots where the symbol just to the left of the new dot
    // is x and all nullable symbols between old dot and the x-position have
    // been consumed.  In practice: find slots where nextSymbol == x, advance.
    var advanced = Set<Slot>()
    for slot in M {
        guard let next = slot.nextSymbol, next == x else { continue }
        advanced.insert(slot.advanced())
    }

    if advanced.isEmpty { return [] }

    // Close under calls.
    return calls(advanced, grammar: grammar)
}

// MARK: - EarleyNFA

/// The Earley NFA: an indexed collection of states G₀ … G_q.
/// Each state G_p is a set of grammar slots (entailment-closed).
public struct EarleyNFA {
    /// All NFA states in enumeration order (G₀ is index 0).
    public let states: [Set<Slot>]

    /// Transition table:  transitions[p][x] = q  (or nil for dead state ⊥).
    public let transitions: [Symbol: [Int?]]  // keyed by symbol, array indexed by state

    /// For convenience: reverse map from state-set to its index.
    let stateIndex: [Set<Slot>: Int]

    /// All symbols that appear as column labels (terminals + nonterminals).
    public let alphabet: [Symbol]

    init(states: [Set<Slot>], transitions: [Symbol: [Int?]], alphabet: [Symbol]) {
        self.states      = states
        self.transitions = transitions
        self.alphabet    = alphabet
        var idx = [Set<Slot>: Int]()
        for (i, s) in states.enumerated() { idx[s] = i }
        self.stateIndex  = idx
    }

    public var stateCount: Int { states.count }

    /// The target state index for a transition from state p on symbol x (nil = ⊥).
    public func transition(from p: Int, on x: Symbol) -> Int? {
        transitions[x]?[p] ?? nil
    }

    /// True if G_p is core (non-empty, contains no dot-at-zero slot).
    public func isCore(_ p: Int) -> Bool {
        let g = states[p]
        return !g.isEmpty && !g.contains(where: { $0.dot == 0 })
    }

    /// The set of nonterminals X such that G_p contains X ::= γ· (complete slots).
    /// Used for completer actions in recET().
    public func completedNonterminals(in p: Int) -> Set<String> {
        Set(states[p].filter(\.isComplete).map(\.production.lhs))
    }
}

// MARK: - NFA Builder

/// Construct the Earley NFA for a given grammar.
/// Algorithm: BFS over reachable states starting from G₀ = Entails(S).
public func buildEarleyNFA(grammar: Grammar) -> EarleyNFA {
    // G₀ = S_LNcall ∪ calls(S_LNcall)   (Section 4.3 / 7.3)
    // S_LNcall = { X ::= ω·γ | X ::= ωγ, ω ⟹* ε }  for the start symbol.
    // In practice calls() over S_LNcall gives G₀.
    let startSlots: Set<Slot> = Set(
        grammar.productions
            .filter { $0.lhs == grammar.startSymbol }
            .map    { Slot(production: $0, dot: 0) }
    )
    let g0 = calls(startSlots, grammar: grammar)

    var allStates: [Set<Slot>] = [g0]
    var stateIndex: [Set<Slot>: Int] = [g0: 0]
    var queue: [Int] = [0]

    // Collect all symbols to iterate over for transitions.
    var symbolSet = Set<Symbol>()
    for s in grammar.allSlots {
        if let next = s.nextSymbol { symbolSet.insert(next) }
    }
    symbolSet.insert(.epsilon)
    let alphabet = Array(symbolSet)

    // Trans[symbol][state] = target state index (optional Int, nil = ⊥)
    // We build it as a dictionary of arrays, resized dynamically.
    var trans: [Symbol: [Int?]] = [:]
    for sym in alphabet { trans[sym] = [] }

    var idx = 0
    while idx < queue.count {
        let p = queue[idx]; idx += 1
        let gp = allStates[p]

        for sym in alphabet {
            let target = move(gp, symbol: sym, grammar: grammar)

            // Ensure arrays are large enough.
            let neededSize = p + 1
            for sym2 in alphabet {
                while trans[sym2]!.count < neededSize { trans[sym2]!.append(nil) }
            }

            if target.isEmpty {
                trans[sym]![p] = nil
            } else if let existing = stateIndex[target] {
                trans[sym]![p] = existing
            } else {
                let newIdx = allStates.count
                allStates.append(target)
                stateIndex[target] = newIdx
                queue.append(newIdx)
                trans[sym]![p] = newIdx
            }
        }
    }

    // Pad all columns to full length.
    let total = allStates.count
    for sym in alphabet {
        while trans[sym]!.count < total { trans[sym]!.append(nil) }
    }

    return EarleyNFA(states: allStates, transitions: trans, alphabet: alphabet)
}
