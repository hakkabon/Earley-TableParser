//
//  NodeLabel.swift
//  Earley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/22.
//  Copyright © 2025 hakkabon software. All rights reserved.
//
//  Uses Grammar library types:
//    NonTerminal — struct with .name: String
//    Symbol      — enum .terminal(Terminal) | .nonTerminal(NonTerminal) | .metaSymbol(MetaSymbol)

import Foundation
import Grammar

/// A node label used for intermediate and packed nodes in the SPPF.
/// It identifies a grammar slot  goal ::= symbols[0…] · symbols[position…]
public struct NodeLabel: Codable {
    /// The LHS nonterminal (head of the production).
    public let goal: NonTerminal
    /// The RHS symbols of the production this label refers to.
    public let symbols: [Symbol]
    /// The dot position: `symbols[0..<position]` have been matched.
    public let position: Int

    public init(goal: NonTerminal, symbols: [Symbol], position: Int) {
        self.goal = goal
        self.symbols = symbols
        self.position = position
    }

    // MARK: Derived properties

    /// True when the dot is past the last symbol (complete slot).
    public var isCompleted: Bool {
        !symbols.indices.contains(position)
    }

    /// True when every symbol in the rhs is nullable.
    public var isNullable: Bool {
        symbols.allSatisfy { symbol in
            switch symbol {
            case .terminal(let t):  return t.isEmpty
            case .nonTerminal:      return false
            case .metaSymbol:       return false
            }
        }
    }

    /// Split the rhs into (alpha, delta) at the dot position.
    public var split: (alpha: [Symbol], delta: [Symbol], dotPosition: Int) {
        let alpha = Array(symbols.prefix(position))
        let delta = Array(symbols.dropFirst(position))
        return (alpha, delta, position)
    }
}

// MARK: - CustomStringConvertible

extension NodeLabel: CustomStringConvertible {

    public var description: String {
        var parts = symbols.map(\.description)
        parts.insert("•", at: min(position, parts.count))
        return "\(goal.name) ::= \(parts.joined(separator: " "))"
    }
}

// MARK: - Hashable / Equatable

extension NodeLabel: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(goal)
        hasher.combine(symbols)
        hasher.combine(position)
    }
}

extension NodeLabel: Equatable {
    public static func == (lhs: NodeLabel, rhs: NodeLabel) -> Bool {
        lhs.goal == rhs.goal && lhs.symbols == rhs.symbols && lhs.position == rhs.position
    }
}

// MARK: - Graphviz rendering

extension NodeLabel {

    /// A compact label string suitable for use inside a Graphviz node.
    public var graphviz: String {
        let rhsStr = symbols.map { symbol -> String in
            switch symbol {
            case .nonTerminal(let nt):   return nt.name
            case .terminal(let t):
                return t.description
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "\n", with: "\\n")
            case .metaSymbol(let ms):   return ms.rawValue
            }
        }.joined(separator: " ")
        return "\(goal.name) ::= \(rhsStr)"
    }
}
