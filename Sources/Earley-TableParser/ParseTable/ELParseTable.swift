// ELParseTable.swift
// Extended-Lookahead (EL) parse table  𝒯_Γ^EL  and the parseET() algorithm.
//
// Reference: Scott & Johnstone (2026), Section 7.2–7.3.
//
// The EL table replaces the SLR(1) lookahead column (A_{p,x} based on
// FOLLOW sets) with two per-state sets that give strictly more precise
// information:
//
//   SELECT(p)  — terminals t for which an action at state p is valid.
//                t ∈ SELECT(p) iff G_p contains a slot μ·ν where
//                  ν →* tv'  (scanner case), OR
//                  ν →* ε  and  t ∈ FOLLOW(Y)  (completer case).
//
//   rLHS(p)    — nonterminals Y with a complete item Y ::= δ· in G_p.
//
// EL table entry:  𝒯_Γ^EL(p, x) = (h, χ₁, χ₂)
//   h   = move index — identical to SL
//   χ₁  = m(G_p, x)  — BSR components for the direct transition on x
//   χ₂  = em(G_p, x) — BSR components for nullable contributions
//
// How parseET() differs from simpleET():
//   • Completer fires for each Y ∈ rLHS(p), but only when a_{j+1} ∈ SELECT(p).
//   • Scanner fires only when a_{j+1} ∈ SELECT(p).
//
// This eliminates the FOLLOW over-approximation and correctly handles
// grammars with hidden left recursion (Section 7.2 of the paper).

import Foundation
import Grammar
import Parser

// MARK: - EL Table Entry

public struct ELTableEntry {
    /// Next NFA state index (nil = ⊥).
    public let nextState: Int?
    /// χ₁ = m(G_p, x): BSR components for the direct transition on x.
    public let chi1: Set<NodeLabel>
    /// χ₂ = em(G_p, x): BSR components for nullable contributions.
    public let chi2: Set<NodeLabel>
}

// MARK: - Per-state EL information

/// The additional per-state data needed by parseET().
public struct ELStateInfo {
    /// SELECT(p): terminal keys for which an action is valid from state p.
    public let selectSet: Set<String>
    /// rLHS(p): nonterminals that are the goal of a complete item in G_p.
    public let rLHS: Set<NonTerminal>
}

// MARK: - EL Parse Table

public struct ELParseTable {
    let entries:   [[String: ELTableEntry]]   // [stateIndex][symbolKey]
    let stateInfo: [ELStateInfo]              // [stateIndex]
    public let nfa: EarleyNFA
    public let grammar: Grammar

    /// Pattern terminals for resolveKey(forToken:) — same purpose as in SLParseTable.
    let patternTerminals: [(terminal: Terminal, key: String)]

    /// staticNullables[state] — see `staticNullableLabels(in:grammar:)` in
    /// SLParseTable.swift. Seeded eagerly by `parseET` whenever a state is
    /// discovered reachable at some input position; fixes the same missing-
    /// BSR-entry gap for closure-time nullable absorption as in the SL table.
    let staticNullables: [Set<NodeLabel>]

    public init(
        entries:    [[String: ELTableEntry]],
        stateInfo:  [ELStateInfo],
        nfa:        EarleyNFA,
        grammar:    Grammar
    ) {
        self.entries          = entries
        self.stateInfo        = stateInfo
        self.nfa              = nfa
        self.grammar          = grammar
        self.patternTerminals = collectPatternTerminals(for: grammar)
        self.staticNullables  = nfa.states.map { staticNullableLabels(in: $0, grammar: grammar) }
    }

    public func entry(state p: Int, symbol x: String) -> ELTableEntry? {
        guard p < entries.count else { return nil }
        return entries[p][x]
    }

    public func info(state p: Int) -> ELStateInfo? {
        guard p < stateInfo.count else { return nil }
        return stateInfo[p]
    }

    /// The static nullable-prefix labels implied by state `p` alone — see
    /// `staticNullableLabels(in:grammar:)`.
    func staticNullableEntries(state p: Int) -> Set<NodeLabel> {
        guard p < staticNullables.count else { return [] }
        return staticNullables[p]
    }

    /// Bridges a raw input token to the key its matching column is stored under.
    /// Identical contract to SLParseTable.resolveKey(forToken:).
    public func resolveKey(forToken token: String) -> String {
        for (terminal, key) in patternTerminals where terminal.matches(.string(string: token)) {
            return key
        }
        return token
    }
}

// MARK: - EL Table Builder

public func buildELParseTable(nfa: EarleyNFA, grammar: Grammar) -> ELParseTable {
    let follow     = grammar.followSets()
    let epsilonSym = Symbol.terminal(Terminal.meta(.eps))

    // ── Step 1: Compute SELECT(p) and rLHS(p) for every NFA state ─────────
    var stateInfos = [ELStateInfo](repeating: ELStateInfo(selectSet: [], rLHS: []), count: nfa.stateCount)

    for p in 0..<nfa.stateCount {
        let gp = nfa.states[p]
        var sel  = Set<String>()
        var rlhs = Set<NonTerminal>()

        for slot in gp {
            if slot.isComplete {
                // Complete item Y ::= δ· contributes to rLHS.
                rlhs.insert(slot.production.goal)
                // FOLLOW(Y) feeds into SELECT (completer case).
                for sym in follow[slot.production.goal] ?? [] {
                    sel.insert(terminalKeyFromSymbol(sym))
                }
            } else {
                // Partial item: FIRST of the remaining suffix feeds into SELECT.
                sel.formUnion(firstTerminalKeys(of: slot.suffix, grammar: grammar, follow: follow,
                                               goal: slot.production.goal))
            }
        }
        sel.remove("")   // remove any empty-string artefacts
        stateInfos[p] = ELStateInfo(selectSet: sel, rLHS: rlhs)
    }

    // ── Step 2: Build per-(state, symbol) EL table entries ────────────────
    var entries = [[String: ELTableEntry]](repeating: [:], count: nfa.stateCount)

    for p in 0..<nfa.stateCount {
        let gp = nfa.states[p]

        // Terminal columns (+ end-of-input $).
        for sym in grammar.terminals.map({ Symbol.terminal($0) }) + [Symbol.terminal(.meta(.eof))] {
            let key  = symbolKey(sym)
            let next = nfa.transition(from: p, on: sym)
            let chi1 = mSets(gp, symbol: sym)
            let chi2: Set<NodeLabel> = next.map { eSets(nfa.states[$0], grammar: grammar) } ?? []
            entries[p][key] = ELTableEntry(nextState: next, chi1: chi1, chi2: chi2)
        }

        // Nonterminal columns.
        for nt in grammar.nonTerminals {
            let sym  = Symbol.nonTerminal(nt)
            let key  = symbolKey(sym)
            let next = nfa.transition(from: p, on: sym)
            let chi1 = mSets(gp, symbol: sym)
            let chi2: Set<NodeLabel> = next.map { eSets(nfa.states[$0], grammar: grammar) } ?? []
            entries[p][key] = ELTableEntry(nextState: next, chi1: chi1, chi2: chi2)
        }

        // ε column.
        let epsNext = nfa.transition(from: p, on: epsilonSym)
        entries[p][epsilonKey] = ELTableEntry(nextState: epsNext, chi1: [], chi2: [])
    }

    return ELParseTable(entries: entries, stateInfo: stateInfos, nfa: nfa, grammar: grammar)
}

// MARK: - parseET()

/// The extended-lookahead Earley Table Traversing Parser (Section 7.3).
///
/// Key differences from simpleET():
///   (i)  Completer fires for each Y ∈ rLHS(p), guarded by a_{j+1} ∈ SELECT(p).
///   (ii) Scanner fires only when a_{j+1} ∈ SELECT(p).
func parseET(table: ELParseTable, input tokens: [String]) -> TableTraversalResult {
    let n = tokens.count

    func a(_ j: Int) -> String {
        j >= 1 && j <= n ? table.resolveKey(forToken: tokens[j - 1]) : eofKey
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)
    var Upsilon = Set<BSR<NodeLabel>>()
    // See simpleET()'s identical mechanism for the full rationale: `lnCallSlots`
    // can fold multi-symbol nullable-prefix absorption into a state's closure
    // without ever crossing a transition, so chi1/chi2 (which only fire on
    // actual transitions) never produce the BSR entries those dot positions
    // need. Seeded per (state, position) since the same state can be reached
    // at several distinct input positions over one parse.
    var staticSeeded = Set<EarleyPair>()

    func seedStaticNullables(state: Int, position: Int) {
        guard staticSeeded.insert(EarleyPair(state: state, backIndex: position)).inserted else { return }
        for label in table.staticNullableEntries(state: state) {
            Upsilon.insert(BSR(label: label, leftExtent: position, pivot: position, rightExtent: position))
        }
    }

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
            seedStaticNullables(state: h, position: j)
            return true
        }
        return false
    }

    // Initialise 𝔼₀ = R₀ = { (0, 0) }
    E[0].insert(EarleyPair(state: 0, backIndex: 0))
    R[0].append(EarleyPair(state: 0, backIndex: 0))
    seedStaticNullables(state: 0, position: 0)

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple
            guard let info = table.info(state: p) else { continue }
            let nextTok = a(j + 1)

            // (i) EL Completer: k ≠ j, a_{j+1} ∈ SELECT(p).
            //     Fire for every Y ∈ rLHS(p), not just FOLLOW-filtered A_{p,x}.
            if k != j && info.selectSet.contains(nextTok) {
                for nt in info.rLHS {
                    let ntKey = nonTerminalKey(nt)
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: ntKey, backIndex: i, pivot: k, position: j)
                    }
                }
            }

            // (ii) ε-transition (always).
            add(state: p, symbol: epsilonKey, backIndex: j, pivot: j, position: j)

            // (iii) Scanner: only when a_{j+1} ∈ SELECT(p).
            if j < n && info.selectSet.contains(nextTok) {
                add(state: p, symbol: nextTok, backIndex: k, pivot: j, position: j + 1)
            }
        }
    }

    let accepted = (n == 0 && table.grammar.productions.contains {
        $0.goal == table.grammar.start && $0.rule.isEmpty
    }) || Upsilon.contains { element in
        element.label.isCompleted && element.label.goal == table.grammar.start &&
        element.leftExtent == 0 && element.rightExtent == n
    }
    return TableTraversalResult(accepted: accepted, bsrSet: Upsilon, earleySets: E)
}

// MARK: - Helpers for SELECT computation

/// Convert any grammar Symbol to the terminal key string used in table columns.
private func terminalKeyFromSymbol(_ sym: Symbol) -> String {
    switch sym {
    case .terminal(let t):     return t.isEmpty ? eofKey : terminalKey(t)
    case .nonTerminal, .metaSymbol: return ""
    }
}

/// FIRST terminal keys of a symbol sequence (stops at first non-nullable symbol).
/// If the entire sequence is nullable, also adds FOLLOW(goal).
private func firstTerminalKeys(
    of syms: [Symbol],
    grammar: Grammar,
    follow: [NonTerminal: Set<Symbol>],
    goal: NonTerminal
) -> Set<String> {
    var result = Set<String>()
    var allNullable = true
    var visited: Set<NonTerminal> = Set()

    for sym in syms {
        switch sym {
        case .terminal(let t):
            if !t.isEmpty { result.insert(terminalKey(t)) }
            allNullable = false
        case .nonTerminal(let nt):
            // Add all terminals that can start a derivation of nt.
            result.formUnion(firstOfNT(nt, grammar: grammar, visited: &visited))
            if !grammar.isNullable(nt) { allNullable = false }
        case .metaSymbol:
            allNullable = false
        }
        if !allNullable { break }
    }

    if allNullable {
        for sym in follow[goal] ?? [] {
            result.insert(terminalKeyFromSymbol(sym))
        }
    }
    return result
}

/// Iterative FIRST terminals of a nonterminal (cycle-safe).
private func firstOfNT(_ nt: NonTerminal, grammar: Grammar, visited: inout Set<NonTerminal>) -> Set<String> {
    guard visited.insert(nt).inserted else { return [] }
    var result = Set<String>()
    for prod in grammar.productions where prod.goal == nt {
        for sym in prod.rule {
            switch sym {
            case .terminal(let t):
                if !t.isEmpty { result.insert(terminalKey(t)) }
                break   // stop at first non-nullable
            case .nonTerminal(let inner):
                result.formUnion(firstOfNT(inner, grammar: grammar, visited: &visited))
                if !grammar.isNullable(inner) { break }
            case .metaSymbol:
                break
            }
        }
    }
    return result
}

// MARK: - Grammar.isNullable([Symbol]) helper

extension Grammar {
    /// True when a sequence of symbols can collectively derive ε.
    func isNullable(_ syms: [Symbol]) -> Bool {
        syms.allSatisfy { sym in
            switch sym {
            case .terminal(let t):     return t.isEmpty
            case .nonTerminal(let nt): return isNullable(nt)
            case .metaSymbol:          return false
            }
        }
    }
}
