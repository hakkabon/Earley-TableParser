// Grammar.swift
// Represents context-free grammars, grammar slots (LR items), and
// the basic sets used throughout Scott & Johnstone (2025).

// MARK: - Grammar Symbols

/// A grammar symbol: either a terminal, nonterminal, or ε.
public enum Symbol: Hashable, CustomStringConvertible {
    case terminal(String)
    case nonterminal(String)
    case epsilon

    public var description: String {
        switch self {
        case .terminal(let s):    return s
        case .nonterminal(let s): return s
        case .epsilon:            return "ε"
        }
    }

    public var isTerminal:    Bool { if case .terminal    = self { return true }; return false }
    public var isNonterminal: Bool { if case .nonterminal = self { return true }; return false }
    public var isEpsilon:     Bool { if case .epsilon     = self { return true }; return false }

    public var name: String? {
        switch self {
        case .terminal(let s), .nonterminal(let s): return s
        case .epsilon: return nil
        }
    }
}

// MARK: - Production

/// A single production rule:  lhs ::= rhs₀ rhs₁ … rhs_{n-1}
/// An empty rhs represents an ε-production.
public struct Production: Hashable, CustomStringConvertible {
    public let lhs: String          // left-hand nonterminal name
    public let rhs: [Symbol]        // right-hand side (may be empty for ε)
    public let id:  Int             // unique index assigned by Grammar

    public var description: String {
        let r = rhs.isEmpty ? "ε" : rhs.map(\.description).joined(separator: " ")
        return "\(lhs) ::= \(r)"
    }
}

// MARK: - Grammar

/// A context-free grammar with a designated start nonterminal.
public struct Grammar {
    public let startSymbol:   String
    public let productions:   [Production]
    public let nonterminals:  Set<String>
    public let terminals:     Set<String>

    /// All slots across all productions.
    public let allSlots: [Slot]

    /// Quick lookup: slots whose lhs is a given nonterminal.
    public let slotsByLHS: [String: [Slot]]

    public init(startSymbol: String, rules: [(lhs: String, rhs: [Symbol])]) {
        self.startSymbol = startSymbol

        var prods: [Production] = []
        var nonterms: Set<String> = []
        var terms: Set<String> = []

        for (idx, (lhs, rhs)) in rules.enumerated() {
            prods.append(Production(lhs: lhs, rhs: rhs, id: idx))
            nonterms.insert(lhs)
            for sym in rhs {
                if case .nonterminal(let n) = sym { nonterms.insert(n) }
                if case .terminal(let t)    = sym { terms.insert(t) }
            }
        }

        self.productions  = prods
        self.nonterminals = nonterms
        self.terminals    = terms

        var slots: [Slot] = []
        var byLHS: [String: [Slot]] = [:]
        for prod in prods {
            for dot in 0...prod.rhs.count {
                let s = Slot(production: prod, dot: dot)
                slots.append(s)
                byLHS[prod.lhs, default: []].append(s)
            }
        }
        self.allSlots    = slots
        self.slotsByLHS  = byLHS
    }

    /// All initial slots  X ::= · γ  for productions with the given lhs.
    public func initialSlots(for lhs: String) -> [Slot] {
        productions
            .filter { $0.lhs == lhs }
            .map    { Slot(production: $0, dot: 0) }
    }

    /// The FIRST set of a sequence of symbols (used in nullable computation).
    /// Returns nil if the sequence can derive ε; otherwise the set of leading terminals.
    public func first(of symbols: [Symbol]) -> (terminals: Set<String>, nullable: Bool) {
        var result = Set<String>()
        for sym in symbols {
            switch sym {
            case .epsilon:
                continue
            case .terminal(let t):
                result.insert(t)
                return (result, false)
            case .nonterminal(let n):
                let (f, canBeNull) = firstOfNonterminal(n)
                result.formUnion(f)
                if !canBeNull { return (result, false) }
            }
        }
        return (result, true)
    }

    // Memoised nullable / FIRST computation.
    private func firstOfNonterminal(_ n: String) -> (Set<String>, Bool) {
        // Simple fixed-point (good enough for moderate grammars).
        var nullable = Set<String>()
        var changed = true
        while changed {
            changed = false
            for prod in productions where !nullable.contains(prod.lhs) {
                let allNull = prod.rhs.allSatisfy {
                    switch $0 {
                    case .epsilon: return true
                    case .nonterminal(let x): return nullable.contains(x)
                    case .terminal: return false
                    }
                }
                if allNull { nullable.insert(prod.lhs); changed = true }
            }
        }
        var firstSets: [String: Set<String>] = [:]
        changed = true
        while changed {
            changed = false
            for prod in productions {
                for sym in prod.rhs {
                    switch sym {
                    case .epsilon: continue
                    case .terminal(let t):
                        if firstSets[prod.lhs, default: []].insert(t).inserted { changed = true }
                        break
                    case .nonterminal(let x):
                        let add = firstSets[x, default: []]
                        for t in add {
                            if firstSets[prod.lhs, default: []].insert(t).inserted { changed = true }
                        }
                        if !nullable.contains(x) { break }
                    }
                }
            }
        }
        return (firstSets[n, default: []], nullable.contains(n))
    }

    /// Compute FOLLOW sets for all nonterminals.
    /// FOLLOW(X) = { t ∈ T | S →* αXtβ for some α,β }
    public func followSets() -> [String: Set<String>] {
        var nullable = Set<String>()
        var firstSets: [String: Set<String>] = [:]

        // Fixed-point nullable
        var changed = true
        while changed {
            changed = false
            for prod in productions where !nullable.contains(prod.lhs) {
                let allNull = prod.rhs.allSatisfy {
                    switch $0 {
                    case .epsilon: return true
                    case .nonterminal(let x): return nullable.contains(x)
                    case .terminal: return false
                    }
                }
                if allNull { nullable.insert(prod.lhs); changed = true }
            }
        }

        // Fixed-point FIRST
        changed = true
        while changed {
            changed = false
            for prod in productions {
                for sym in prod.rhs {
                    switch sym {
                    case .epsilon: continue
                    case .terminal(let t):
                        if firstSets[prod.lhs, default: []].insert(t).inserted { changed = true }
                        break
                    case .nonterminal(let x):
                        for t in firstSets[x, default: []] {
                            if firstSets[prod.lhs, default: []].insert(t).inserted { changed = true }
                        }
                        if !nullable.contains(x) { break }
                    }
                }
            }
        }

        // FOLLOW fixed-point
        var follow: [String: Set<String>] = [:]
        follow[startSymbol, default: []].insert("$")
        changed = true
        while changed {
            changed = false
            for prod in productions {
                for (i, sym) in prod.rhs.enumerated() {
                    guard case .nonterminal(let B) = sym else { continue }
                    let beta = Array(prod.rhs[(i+1)...])
                    let (firstBeta, betaNullable) = first(of: beta)
                    for t in firstBeta {
                        if follow[B, default: []].insert(t).inserted { changed = true }
                    }
                    if betaNullable {
                        for t in follow[prod.lhs, default: []] {
                            if follow[B, default: []].insert(t).inserted { changed = true }
                        }
                    }
                }
            }
        }
        return follow
    }

    /// True if a string of symbols can derive ε.
    public func isNullable(_ symbols: [Symbol]) -> Bool {
        first(of: symbols).nullable
    }

    /// True if a single nonterminal can derive ε.
    public func isNullableNonterminal(_ name: String) -> Bool {
        isNullable([.nonterminal(name)])
    }
}
