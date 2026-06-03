//
//  GrammarSlot.swift
//  Earley-TableParser
//
//  A grammar slot (LR/Earley item without a back-index).
//  A slot  X ::= α · β  is identified by (production, dot).
//  The dot ranges from 0 (before all rhs symbols) to rule.count (after all).
//
//  Uses the Grammar library's Production type:
//    production.goal : NonTerminal  — the LHS
//    production.rule : [Symbol]     — the RHS

import Foundation
import Grammar

/// A grammar slot  X ::= α · β.
public struct Slot: Hashable, CustomStringConvertible {

    public let production: Production
    /// Index of the symbol *after* the dot (0 … rule.count).
    public let dot: Int

    public init(production: Production, dot: Int) {
        self.production = production
        self.dot = dot
    }

    // MARK: Derived properties

    /// The symbol immediately after the dot, or nil when the slot is complete.
    public var nextSymbol: Symbol? {
        guard dot < production.rule.count else { return nil }
        return production.rule[dot]
    }

    /// True when the dot is past the last symbol (slot is "complete").
    public var isComplete: Bool { dot == production.rule.count }

    /// Return a new slot with the dot advanced by one position.
    public func advanced() -> Slot {
        precondition(!isComplete, "Cannot advance a complete slot")
        return Slot(production: production, dot: dot + 1)
    }

    /// All symbols to the right of the dot.
    public var suffix: [Symbol] { Array(production.rule[dot...]) }

    /// All symbols to the left of the dot (the "handled" prefix).
    public var prefix: [Symbol] { Array(production.rule[..<dot]) }

    // MARK: CustomStringConvertible

    public var description: String {
        var rhs = production.rule.map(\.description)
        rhs.insert("·", at: dot)
        return "\(production.goal.name) ::= \(rhs.joined(separator: " "))"
    }
}

// MARK: - Grammar extension: allSlots

extension Grammar {
    /// All grammar slots across every production.
    /// Needed by the NFA builder to enumerate the full alphabet.
    public var allSlots: [Slot] {
        var slots: [Slot] = []
        for prod in productions {
            for dot in 0...prod.rule.count {
                slots.append(Slot(production: prod, dot: dot))
            }
        }
        return slots
    }

    /// Initial slots  X ::= · γ  for every production of the given nonterminal.
    public func initialSlots(for nt: NonTerminal) -> [Slot] {
        productions
            .filter { $0.goal == nt }
            .map    { Slot(production: $0, dot: 0) }
    }
}
