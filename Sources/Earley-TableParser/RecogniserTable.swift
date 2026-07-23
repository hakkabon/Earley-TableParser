// RecogniserTable.swift
// Builds the recogniser table  𝒯_Γ  and implements the  recET()  algorithm
// from Section 5 of Scott & Johnstone (2026).
//
// Table entry  𝒯_Γ(p, x) = (m, A)  where
//   m  is the target NFA state index (or ⊥ = nil) after transitioning on x
//   A  is the set of nonterminals Y such that G_p contains  Y ::= γ·
//      and  x ∈ FOLLOW(Y)  — the SLR(1)-style lookahead for completers.
//
// Grammar library API:
//   production.goal : NonTerminal
//   production.rule : [Symbol]
//   grammar.followSets() -> [NonTerminal: Set<Symbol>]
//   grammar.terminals   : Set<Terminal>
//   grammar.nonTerminals: Set<NonTerminal>
//   Symbol.terminal(Terminal) / .nonTerminal(NonTerminal)

import Foundation
import Grammar

// MARK: - Recogniser Table Entry

public struct RecTableEntry {
    /// Target state after consuming x (nil = dead / ⊥).
    public let nextState: Int?
    /// Nonterminals completed at this state whose FOLLOW contains x.
    public let completedNTs: Set<NonTerminal>
}

// MARK: - Recogniser Table  𝒯_Γ

/// The pre-computed recogniser table.
/// `table[p][x]` gives the entry for state `p` and typed column key `x`.
public struct RecogniserTable {
    let entries: [[TableKey: RecTableEntry]]
    let nfa: EarleyNFA
    /// The grammar start symbol. Acceptance must not infer this from G₀,
    /// whose entailment closure normally contains slots for several goals.
    public let start: NonTerminal

    private let keyResolver: TableKeyResolver

    init(
        entries: [[TableKey: RecTableEntry]],
        nfa: EarleyNFA,
        start: NonTerminal,
        keyResolver: TableKeyResolver
    ) {
        self.entries = entries
        self.nfa = nfa
        self.start = start
        self.keyResolver = keyResolver
    }

    public var stateCount: Int { entries.count }

    /// Looks up the entry for state `p` and typed column key `x`.
    public func entry(state p: Int, symbol x: TableKey) -> RecTableEntry? {
        guard entries.indices.contains(p) else { return nil }
        return entries[p][x]
    }

    /// The completed nonterminals at state p with lookahead x.
    public func completers(state p: Int, symbol x: TableKey) -> Set<NonTerminal> {
        entry(state: p, symbol: x)?.completedNTs ?? []
    }

    /// Next state from p on symbol key x (nil = ⊥).
    public func nextState(from p: Int, symbol x: TableKey) -> Int? {
        entry(state: p, symbol: x)?.nextState
    }

    /// Resolves a concrete input token to its typed terminal column.
    ///
    /// For an ordinary `.string` grammar terminal this is a no-op (the token's
    /// Exact literal terminals are preferred over regex/range/list patterns.
    /// An unmatched token still produces a terminal key, which simply misses
    /// every table column.
    public func key(forToken token: String) -> TableKey {
        keyResolver.key(forToken: token)
    }
}

// MARK: - Table Builder

public func buildRecogniserTable(nfa: EarleyNFA, grammar: Grammar) -> RecogniserTable {
    let follow = grammar.followSets()   // [NonTerminal: Set<Symbol>]
    let epsilonSym: Symbol = .terminal(.meta(.eps))

    var entries = [[TableKey: RecTableEntry]](repeating: [:], count: nfa.stateCount)

    for p in 0..<nfa.stateCount {
        let gp = nfa.states[p]

        // ── Terminal columns (including the end-of-input sentinel "$") ──
        let terminalSymbols: [Symbol] = grammar.terminals.map { .terminal($0) }
            + [.terminal(.meta(.eof))]   // "$" / end-of-input

        for sym in terminalSymbols {
            guard let key = TableKey(symbol: sym) else { continue }
            let next = nfa.transition(from: p, on: sym)

            // A_{p,x} = { Y | Y ::= γ· ∈ G_p  and  sym ∈ FOLLOW(Y) }
            var completed = Set<NonTerminal>()
            for slot in gp where slot.isComplete {
                let y = slot.production.goal
                if follow[y]?.contains(sym) == true {
                    completed.insert(y)
                }
            }
            entries[p][key] = RecTableEntry(nextState: next, completedNTs: completed)
        }

        // ── Nonterminal columns ──
        for nt in grammar.nonTerminals {
            let sym = Symbol.nonTerminal(nt)
            let key = TableKey.nonTerminal(nt)
            let next = nfa.transition(from: p, on: sym)
            // Completer sets are only indexed by terminals in recET().
            entries[p][key] = RecTableEntry(nextState: next, completedNTs: [])
        }

        // ── ε column ──
        let epsNext = nfa.transition(from: p, on: epsilonSym)
        entries[p][.epsilon] = RecTableEntry(nextState: epsNext, completedNTs: [])
    }

    return RecogniserTable(
        entries: entries,
        nfa: nfa,
        start: grammar.start,
        keyResolver: TableKeyResolver(grammar: grammar))
}

// MARK: - recET() Recogniser

/// The Earley recogniser from Section 5.2 of Scott & Johnstone (2026).
///
/// Each Earley set 𝔼_j contains pairs (state, backIndex):
///   state     = current NFA state index
///   backIndex = input position where the most recent ε-transition originated
///
/// Returns true iff the token sequence is in the grammar's language.
public func recET(table: RecogniserTable, input tokens: [String]) -> Bool {
    let n = tokens.count

    // a(j) = tokens[j-1] for j in 1…n;  a(n+1) = "$"
    //
    // Concrete token text is resolved to its literal or pattern-terminal
    // column. The synthetic position after the input uses a distinct EOF key.
    func a(_ j: Int) -> TableKey {
        j >= 1 && j <= n ? table.key(forToken: tokens[j - 1]) : .endOfInput
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)

    /// ADD: transition from state p on symbol key x with back-index i, targeting E[j].
    func add(state p: Int, symbol x: TableKey, backIndex i: Int, position j: Int) {
        guard let entry = table.entry(state: p, symbol: x),
              let h = entry.nextState else { return }
        let pair = EarleyPair(state: h, backIndex: i)
        if E[j].insert(pair).inserted {
            R[j].append(pair)
        }
    }

    // Initialise: 𝔼₀ = R₀ = { (0, 0) }
    E[0].insert(EarleyPair(state: 0, backIndex: 0))
    R[0].append(EarleyPair(state: 0, backIndex: 0))

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple

            // (i) Completer: look up completed nonterminals and propagate.
            // Zero-width completions (k == j) are required for nullable rules.
            let nextTok = a(j + 1)
            for nt in table.completers(state: p, symbol: nextTok) {
                let ntKey = TableKey.nonTerminal(nt)
                for (h, i) in E[k].map(\.asTuple) {
                    add(state: h, symbol: ntKey, backIndex: i, position: j)
                }
            }

            // (ii) ε-transition: enter the called-only state at the current
            // input position.
            add(state: p, symbol: .epsilon, backIndex: j, position: j)

            // (iii) Scanner: if j < n, ADD(p, a_{j+1}, k, j+1)
            if j < n {
                add(state: p, symbol: a(j + 1), backIndex: k, position: j + 1)
            }
        }
    }

    // Determine the start nonterminal from NFA state 0.
    // Accept if some (p, 0) ∈ 𝔼_n where G_p contains a complete start item.
    return E[n].contains { pair in
        pair.backIndex == 0 &&
        table.nfa.states[pair.state].contains { slot in
            slot.isComplete && slot.production.goal == table.start
        }
    }
}

// MARK: - EarleyPair

public struct EarleyPair: Hashable {
    public let state:     Int
    public let backIndex: Int
    var asTuple: (Int, Int) { (state, backIndex) }
}
