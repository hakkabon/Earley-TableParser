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
    /// SELECT(p): terminal or EOF columns for which an action is valid.
    public let selectSet: Set<TableKey>
    /// rLHS(p): nonterminals that are the goal of a complete item in G_p.
    public let rLHS: Set<NonTerminal>
}

// MARK: - EL Parse Table

public struct ELParseTable {
    let entries:   [[TableKey: ELTableEntry]]
    let stateInfo: [ELStateInfo]
    public let nfa: EarleyNFA
    public let grammar: Grammar

    private let keyResolver: TableKeyResolver

    public init(
        entries:    [[TableKey: ELTableEntry]],
        stateInfo:  [ELStateInfo],
        nfa:        EarleyNFA,
        grammar:    Grammar
    ) {
        self.entries          = entries
        self.stateInfo        = stateInfo
        self.nfa              = nfa
        self.grammar          = grammar
        self.keyResolver      = TableKeyResolver(grammar: grammar)
    }

    /// Looks up the entry for state `p` and typed column key `x`.
    public func entry(state p: Int, symbol x: TableKey) -> ELTableEntry? {
        guard entries.indices.contains(p) else { return nil }
        return entries[p][x]
    }

    public func info(state p: Int) -> ELStateInfo? {
        guard p < stateInfo.count else { return nil }
        return stateInfo[p]
    }

    /// Resolves a concrete input token to its typed literal or pattern column.
    public func key(forToken token: String) -> TableKey {
        keyResolver.key(forToken: token)
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
        var sel  = Set<TableKey>()
        var rlhs = Set<NonTerminal>()

        for slot in gp {
            if slot.isComplete {
                // Complete item Y ::= δ· contributes to rLHS.
                rlhs.insert(slot.production.goal)
                // FOLLOW(Y) feeds into SELECT (completer case).
                for sym in follow[slot.production.goal] ?? [] {
                    if let key = terminalTableKey(from: sym) {
                        sel.insert(key)
                    }
                }
            } else {
                // Partial item: FIRST of the remaining suffix feeds into SELECT.
                sel.formUnion(firstTerminalKeys(of: slot.suffix, grammar: grammar, follow: follow,
                                               goal: slot.production.goal))
            }
        }
        stateInfos[p] = ELStateInfo(selectSet: sel, rLHS: rlhs)
    }

    // ── Step 2: Build per-(state, symbol) EL table entries ────────────────
    var entries = [[TableKey: ELTableEntry]](repeating: [:], count: nfa.stateCount)

    for p in 0..<nfa.stateCount {
        let gp = nfa.states[p]

        // Terminal columns (+ end-of-input $).
        for sym in grammar.terminals.map({ Symbol.terminal($0) }) + [Symbol.terminal(.meta(.eof))] {
            guard let key = TableKey(symbol: sym) else { continue }
            let next = nfa.transition(from: p, on: sym)
            let chi1 = mSets(gp, symbol: sym)
            let chi2: Set<NodeLabel> = next.map { eSets(nfa.states[$0], grammar: grammar) } ?? []
            entries[p][key] = ELTableEntry(nextState: next, chi1: chi1, chi2: chi2)
        }

        // Nonterminal columns.
        for nt in grammar.nonTerminals {
            let sym  = Symbol.nonTerminal(nt)
            let key  = TableKey.nonTerminal(nt)
            let next = nfa.transition(from: p, on: sym)
            let chi1 = mSets(gp, symbol: sym)
            let chi2: Set<NodeLabel> = next.map { eSets(nfa.states[$0], grammar: grammar) } ?? []
            entries[p][key] = ELTableEntry(nextState: next, chi1: chi1, chi2: chi2)
        }

        // ε column.
        let epsNext = nfa.transition(from: p, on: epsilonSym)
        entries[p][.epsilon] = ELTableEntry(nextState: epsNext, chi1: [], chi2: [])
    }

    return ELParseTable(entries: entries, stateInfo: stateInfos, nfa: nfa, grammar: grammar)
}

// MARK: - parseET()

/// The extended-lookahead Earley Table Traversing Parser (Section 7.3).
///
/// Key differences from simpleET():
///   (i)  Completer fires for each Y ∈ rLHS(p), guarded by a_{j+1} ∈ SELECT(p),
///        including zero-width nullable completions.
///   (ii) Scanner fires only when a_{j+1} ∈ SELECT(p).
func parseET(table: ELParseTable, input tokens: [String]) -> TableTraversalResult {
    let n = tokens.count

    func a(_ j: Int) -> TableKey {
        j >= 1 && j <= n ? table.key(forToken: tokens[j - 1]) : .endOfInput
    }

    var E = [Set<EarleyPair>](repeating: [], count: n + 1)
    var R = [[EarleyPair]](repeating: [], count: n + 1)
    var Upsilon = Set<BSR<NodeLabel>>()

    @discardableResult
    func add(state p: Int, symbol x: TableKey, backIndex i: Int, pivot k: Int, position j: Int) -> Bool {
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

    // Initialise 𝔼₀ = R₀ = { (0, 0) }
    E[0].insert(EarleyPair(state: 0, backIndex: 0))
    R[0].append(EarleyPair(state: 0, backIndex: 0))

    for j in 0...n {
        while !R[j].isEmpty {
            let (p, k) = R[j].removeLast().asTuple
            guard let info = table.info(state: p) else { continue }
            let nextTok = a(j + 1)

            // (i) EL Completer: a_{j+1} ∈ SELECT(p), including k == j
            //     for zero-width nullable completions.
            //     Fire for every Y ∈ rLHS(p), not just FOLLOW-filtered A_{p,x}.
            if info.selectSet.contains(nextTok) {
                for nt in info.rLHS {
                    let ntKey = TableKey.nonTerminal(nt)
                    for (h, i) in E[k].map(\.asTuple) {
                        add(state: h, symbol: ntKey, backIndex: i, pivot: k, position: j)
                    }
                }
            }

            // (ii) ε-transition (always): enter called-only state.
            add(state: p, symbol: .epsilon, backIndex: j, pivot: j, position: j)

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

/// Converts a terminal grammar symbol to its canonical table column.
private func terminalTableKey(from symbol: Symbol) -> TableKey? {
    guard case .terminal = symbol else { return nil }
    return TableKey(symbol: symbol)
}

/// FIRST terminal columns of a symbol sequence (stops at the first
/// non-nullable symbol).
/// If the entire sequence is nullable, also adds FOLLOW(goal).
private func firstTerminalKeys(
    of syms: [Symbol],
    grammar: Grammar,
    follow: [NonTerminal: Set<Symbol>],
    goal: NonTerminal
) -> Set<TableKey> {
    var result = Set<TableKey>()
    var allNullable = true
    var visited: Set<NonTerminal> = Set()

    for sym in syms {
        switch sym {
        case .terminal(let t):
            if !t.isEmpty { result.insert(tableKey(for: t)) }
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
            if let key = terminalTableKey(from: sym) {
                result.insert(key)
            }
        }
    }
    return result
}

/// Iterative FIRST terminals of a nonterminal (cycle-safe).
private func firstOfNT(
    _ nt: NonTerminal,
    grammar: Grammar,
    visited: inout Set<NonTerminal>
) -> Set<TableKey> {
    guard visited.insert(nt).inserted else { return [] }
    var result = Set<TableKey>()
    for prod in grammar.productions where prod.goal == nt {
        for sym in prod.rule {
            switch sym {
            case .terminal(let t):
                if !t.isEmpty { result.insert(tableKey(for: t)) }
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
