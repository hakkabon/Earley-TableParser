// EarleyNFA.swift
// Constructs the Earley NFA (Γ_NFA) from a grammar by computing
// calls(M) and move(M, x) as defined in Section 4.2 of the paper.
//
// The key ideas:
//   calls(M)   = smallest set of slots that includes all "left-null-call" slots
//                reachable from M via nonterminal calls.
//   move(M, x) = core slots reached by matching x; the explicit ε edge enters
//                called-only states so that origins are not conflated.
//
// NFA states alternate between core move sets and called-only sets.
// States are indexed G₀, G₁, … G_q once enumerated.
//
// Grammar library API used:
//   production.goal  : NonTerminal
//   production.rule  : [Symbol]
//   Symbol.terminal(Terminal)  /  .nonTerminal(NonTerminal)  /  .metaSymbol(MetaSymbol)
//   Terminal.meta(.eps)        — epsilon terminal
//   grammar.isNullable(_ nt: NonTerminal)  /  grammar.isNullable(_:[Symbol])

import Foundation
import Grammar

// MARK: - Epsilon helper

/// True when a Symbol represents the empty string (ε / λ).
func isEpsilonSymbol(_ sym: Symbol) -> Bool {
    switch sym {
    case .terminal(let t): return t.isEmpty
    default: return false
    }
}

// MARK: - calls()

/// Compute calls(M): the smallest superset of M satisfying:
///   (i)  If (X ::= α · Y δ) ∈ M        → add all LNcall slots for Y
///   (ii) If (U ::= τ · V v) ∈ calls(M) → add all LNcall slots for V
///
/// LNcall(X) = { X ::= ω·γ | X ::= ωγ ∈ P, ω ⟹* ε }
///
/// (Scott & Johnstone 2026, Section 4.2)
func calls(_ M: Set<Slot>, grammar: Grammar) -> Set<Slot> {
    var result = M
    var worklist = Array(M)

    while let slot = worklist.popLast() {
        // For each slot, if the symbol after the dot is a nonterminal,
        // add all its left-null-call slots.
        guard let next = slot.nextSymbol,
              case .nonTerminal(let nt) = next else { continue }

        for newSlot in grammar.lnCallSlots(for: nt) {
            if result.insert(newSlot).inserted {
                worklist.append(newSlot)
            }
        }
    }
    return result
}

// MARK: - move()

/// Compute move(M, x): slots reachable by consuming symbol x from state M.
///
///   move(M, x) for x ≠ ε:
///     = { X ::= αx·β | (X ::= α·xβ) ∈ M }
///
///   move(M, ε):
///     = calls(M) ∖ M  if M is core (non-empty, no dot-at-zero slot)
///     = ∅         otherwise
///
/// (Scott & Johnstone 2026, Section 4.2)
func move(_ M: Set<Slot>, symbol x: Symbol, grammar: Grammar) -> Set<Slot> {
    // ε-transition
    if isEpsilonSymbol(x) {
        let isCore = !M.isEmpty && !M.contains(where: { $0.dot == 0 })
        // Keep kernel and called items in distinct NFA states: their Earley
        // pairs carry different origins.  Nullable calls are completed by the
        // normal completer, including when their span is zero-width.
        return isCore ? calls(M, grammar: grammar).subtracting(M) : []
    }

    // Ordinary symbol: advance all slots whose next-symbol matches x.
    var advanced = Set<Slot>()
    for slot in M {
        guard let next = slot.nextSymbol, next == x else { continue }
        advanced.insert(slot.advanced())
    }
    // Do not close an ordinary transition under `calls` here.  The explicit
    // ε-transition below is what changes a core state into its call-closed
    // state, and recET/simpleET assign that transition the current input
    // position as its back index.  Folding the closure into this transition
    // mixes kernel items (whose origin must be preserved) with newly called
    // items (whose origin is the current position) in one Earley pair.
    return advanced
}

// MARK: - EarleyNFA

/// The Earley NFA: an indexed collection of states G₀ … G_q.
/// States are either core move sets or called-only sets of grammar slots.
public struct EarleyNFA {
    /// All NFA states in BFS-enumeration order (G₀ is index 0).
    public let states: [Set<Slot>]
    /// Transition table: transitions[symbol][stateIndex] = targetStateIndex (nil = ⊥).
    public let transitions: [Symbol: [Int?]]
    /// Reverse map: set-of-slots → state index.
    let stateIndex: [Set<Slot>: Int]
    /// All symbols that label NFA columns (terminals + nonterminals, excluding metaSymbols).
    public let alphabet: [Symbol]

    init(states: [Set<Slot>], transitions: [Symbol: [Int?]], alphabet: [Symbol]) {
        self.states      = states
        self.transitions = transitions
        self.alphabet    = alphabet
        var idx = [Set<Slot>: Int]()
        for (i, s) in states.enumerated() { idx[s] = i }
        self.stateIndex = idx
    }

    public var stateCount: Int { states.count }

    /// The target state index when transitioning from state p on symbol x (nil = ⊥).
    public func transition(from p: Int, on x: Symbol) -> Int? {
        transitions[x]?[p] ?? nil
    }

    /// True if G_p is a core state (non-empty, contains no dot-at-zero slot).
    public func isCore(_ p: Int) -> Bool {
        let g = states[p]
        return !g.isEmpty && !g.contains(where: { $0.dot == 0 })
    }

    /// Nonterminals X such that G_p contains a complete slot  X ::= γ·.
    public func completedNonterminals(in p: Int) -> Set<NonTerminal> {
        Set(states[p].filter(\.isComplete).map(\.production.goal))
    }
}

// MARK: - Grammar extension for LNcall (left-null-call slots)

extension Grammar {
    /// Compute LNcall(X): all slots X ::= ω·γ where ω ⟹* ε (ω is nullable).
    func lnCallSlots(for nt: NonTerminal) -> [Slot] {
        var result: [Slot] = []
        for prod in productions where prod.goal == nt {
            // Walk dot positions: add slot X ::= ω·γ when all of ω is nullable.
            // The prefix ω = rule[0..<dot] must be nullable.
            for dot in 0...prod.rule.count {
                let prefix = Array(prod.rule[..<dot])
                if isNullable(prefix) {
                    result.append(Slot(production: prod, dot: dot))
                } else {
                    // Once a symbol in the prefix is non-nullable, further
                    // prefixes won't be nullable either.
                    break
                }
            }
        }
        return result
    }
}

// MARK: - NFA Builder

/// Build the Earley NFA for a grammar using BFS from the call closure of the
/// start productions' dot-zero slots.
///
/// (Scott & Johnstone 2026, Section 4.3)
public func buildEarleyNFA(grammar: Grammar) -> EarleyNFA {
    let startSlots = Set(
        grammar.productions
            .filter { $0.goal == grammar.start }
            .map { Slot(production: $0, dot: 0) }
    )
    let g0 = calls(startSlots, grammar: grammar)

    var allStates: [Set<Slot>] = [g0]
    var stateIndex: [Set<Slot>: Int] = [g0: 0]
    var queue: [Int] = [0]

    // Build the alphabet: every terminal and nonterminal that appears
    // in any production, plus the epsilon symbol.
    // Note: We don't include MetaSymbol literals (like "[", "]", "{", etc.)
    // as they're EBNF constructs removed during standardization.
    var symbolSet = Set<Symbol>()
    
    // Collect all symbols from all productions
    for prod in grammar.productions {
        for sym in prod.rule {
            switch sym {
            case .terminal, .nonTerminal:
                symbolSet.insert(sym)
            case .metaSymbol:
                // MetaSymbols are EBNF constructs; skip them.
                // They should be eliminated during standardization anyway.
                break
            }
        }
    }
    
    // Add the epsilon symbol as an explicit column.
    let epsilonSym: Symbol = .terminal(.meta(.eps))
    symbolSet.insert(epsilonSym)
    
    let alphabet = Array(symbolSet)

    // Build transition table as Symbol → [Int?] (indexed by state index).
    var trans: [Symbol: [Int?]] = [:]
    for sym in alphabet { trans[sym] = [] }

    var bfsIdx = 0
    while bfsIdx < queue.count {
        let p = queue[bfsIdx]; bfsIdx += 1
        let gp = allStates[p]

        // Ensure all arrays are long enough for state p.
        for sym in alphabet {
            while trans[sym]!.count <= p { trans[sym]!.append(nil) }
        }

        for sym in alphabet {
            let target = move(gp, symbol: sym, grammar: grammar)
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
