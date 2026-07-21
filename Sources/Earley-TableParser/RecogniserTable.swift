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
/// `table[p][x]` gives the entry for state p and symbol-name string x.
public struct RecogniserTable {
    let entries: [[String: RecTableEntry]]   // indexed by state, keyed by symbol key
    let nfa: EarleyNFA
    /// The grammar start symbol. Acceptance must not infer this from G₀,
    /// whose entailment closure normally contains slots for several goals.
    public let start: NonTerminal

    /// Every grammar terminal that isn't `.string` — i.e. a `.regularExpression`,
    /// `.characterRange`, or `.stringList` terminal, ordinarily one resolved
    /// from a `lexical { }` declaration — paired with the same `terminalKey(_:)`
    /// string its table entries are actually stored under.
    ///
    /// `terminalKey(_:)` on a pattern terminal returns the *pattern's own*
    /// text (a regex's source via `.description`, a range's bounds, ...), not
    /// anything a concrete input token could ever equal — so `entries[p][tok]`
    /// can never find those columns by a direct string lookup, no matter what
    /// the token actually is. `resolveKey(forToken:)` is the bridge.
    let patternTerminals: [(terminal: Terminal, key: String)]

    public var stateCount: Int { entries.count }

    /// Look up entry for state p and symbol key x.
    public func entry(state p: Int, symbol x: String) -> RecTableEntry? {
        guard p < entries.count else { return nil }
        return entries[p][x]
    }

    /// The completed nonterminals at state p with lookahead x.
    public func completers(state p: Int, symbol x: String) -> Set<NonTerminal> {
        entry(state: p, symbol: x)?.completedNTs ?? []
    }

    /// Next state from p on symbol key x (nil = ⊥).
    public func nextState(from p: Int, symbol x: String) -> Int? {
        entry(state: p, symbol: x)?.nextState
    }

    /// Resolves a raw input token's own literal text to the key its matching
    /// table column is actually stored under.
    ///
    /// For an ordinary `.string` grammar terminal this is a no-op (the token's
    /// own text already is the column key). For a `.regularExpression`/
    /// `.characterRange`/`.stringList` grammar terminal, this checks `token`
    /// against each pattern with `Terminal.matches(_:)` (the asymmetric
    /// pattern-vs-lexeme check — see `Terminal.matches(_:)` in the Grammar
    /// package) and, on a match, returns that pattern's own key instead.
    /// Falls back to `token` unchanged when nothing matches, so a genuinely
    /// invalid token still correctly misses every column.
    public func resolveKey(forToken token: String) -> String {
        for (terminal, key) in patternTerminals where terminal.matches(.string(string: token)) {
            return key
        }
        return token
    }
}

// MARK: - Table Builder

public func buildRecogniserTable(nfa: EarleyNFA, grammar: Grammar) -> RecogniserTable {
    let follow = grammar.followSets()   // [NonTerminal: Set<Symbol>]
    let epsilonSym: Symbol = .terminal(.meta(.eps))

    var entries = [[String: RecTableEntry]](repeating: [:], count: nfa.stateCount)

    for p in 0..<nfa.stateCount {
        let gp = nfa.states[p]

        // ── Terminal columns (including the end-of-input sentinel "$") ──
        let terminalSymbols: [Symbol] = grammar.terminals.map { .terminal($0) }
            + [.terminal(.meta(.eof))]   // "$" / end-of-input

        for sym in terminalSymbols {
            let key = symbolKey(sym)
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
            let key = symbolKey(sym)
            let next = nfa.transition(from: p, on: sym)
            // Completer sets are only indexed by terminals in recET().
            entries[p][key] = RecTableEntry(nextState: next, completedNTs: [])
        }

        // ── ε column ──
        let epsNext = nfa.transition(from: p, on: epsilonSym)
        entries[p][epsilonKey] = RecTableEntry(nextState: epsNext, completedNTs: [])
    }

    return RecogniserTable(
        entries: entries,
        nfa: nfa,
        start: grammar.start,
        patternTerminals: collectPatternTerminals(for: grammar))
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
    // Resolved via table.resolveKey(forToken:) rather than returned raw: a
    // token's own literal text (e.g. "42") only equals a table column key
    // directly for plain .string grammar terminals. A .regularExpression/
    // .characterRange/.stringList terminal's column is keyed by the
    // *pattern's* own text, so matching those requires this indirection —
    // see RecogniserTable.resolveKey(forToken:).
    func a(_ j: Int) -> String {
        j >= 1 && j <= n ? table.resolveKey(forToken: tokens[j - 1]) : eofKey
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)

    /// ADD: transition from state p on symbol key x with back-index i, targeting E[j].
    func add(state p: Int, symbol x: String, backIndex i: Int, position j: Int) {
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

            // (i) Completer: k ≠ j — look up completed nonterminals and propagate.
            if k != j {
                let nextTok = a(j + 1)
                for nt in table.completers(state: p, symbol: nextTok) {
                    let ntKey = nonTerminalKey(nt)
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: ntKey, backIndex: i, position: j)
                    }
                }
            }

            // (ii) ε-transition: ADD(p, ε, j, j)
            add(state: p, symbol: epsilonKey, backIndex: j, position: j)

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

// MARK: - Symbol key helpers

/// The string key used as the dictionary index for a Symbol in the tables.
/// Terminals are keyed by their string description; nonterminals by their name.
func symbolKey(_ sym: Symbol) -> String {
    switch sym {
    case .terminal(let t):    return terminalKey(t)
    case .nonTerminal(let nt): return nonTerminalKey(nt)
    case .metaSymbol(let ms): return ms.rawValue
    }
}

func terminalKey(_ t: Terminal) -> String {
    switch t {
    case .string(let s): return s
    case .meta(let m):   return m.rawValue
    default:             return t.description
    }
}

func nonTerminalKey(_ nt: NonTerminal) -> String { nt.name }

/// Every grammar terminal that isn't `.string` (i.e. resolved from a
/// `lexical { }` regex/range/list declaration), paired with its `terminalKey(_:)`
/// string — shared by `RecogniserTable` and `SLParseTable`'s `resolveKey(forToken:)`.
/// See `RecogniserTable.patternTerminals`'s doc comment for why this exists.
func collectPatternTerminals(for grammar: Grammar) -> [(terminal: Terminal, key: String)] {
    grammar.terminals.compactMap { terminal in
        switch terminal {
        case .string, .meta: return nil
        case .characterRange, .stringList, .regularExpression:
            return (terminal, terminalKey(terminal))
        }
    }
}

/// The dictionary key for the epsilon column.
let epsilonKey: String = MetaTerminal.eps.rawValue   // "ε"

/// The dictionary key for the end-of-input sentinel.
let eofKey: String = MetaTerminal.eof.rawValue        // "$"
