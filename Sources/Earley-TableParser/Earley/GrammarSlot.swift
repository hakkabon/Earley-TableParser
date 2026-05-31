//
//  GrammarSlot.swift
//  Earley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/01.
//

import Foundation
import Grammar

/// Grammar Slot is roughly a LR / Earley item without back-index.
/// A grammar slot  X ::= α · β  is identified by (productionId, dot).
/// The dot ranges from 0 (before all rhs symbols) to rhs.count (after all).
public struct Slot: Hashable, CustomStringConvertible {
    public let production: Production
    public let dot: Int             // index of the symbol *after* the dot

    /// The symbol immediately after the dot, or nil when dot == rhs.count.
    public var nextSymbol: Symbol? {
        guard dot < production.rhs.count else { return nil }
        return production.rhs[dot]
    }

    /// True when the dot is at the end (slot is "complete").
    public var isComplete: Bool { dot == production.rhs.count }

    /// The slot with the dot advanced by one position.
    public func advanced() -> Slot {
        precondition(!isComplete)
        return Slot(production: production, dot: dot + 1)
    }

    /// All symbols to the right of the dot.
    public var suffix: [Symbol] { Array(production.rhs[dot...]) }

    public var description: String {
        var rhs = production.rhs.map(\.description)
        rhs.insert("·", at: dot)
        return "\(production.lhs) ::= \(rhs.joined(separator: " "))"
    }
}
