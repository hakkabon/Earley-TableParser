import Foundation
import Grammar

/// A type-safe column identifier shared by the recogniser, SL, and EL tables.
///
/// Keeping the symbol category in the key prevents equal spellings from
/// aliasing one another. For example, the literal terminal `"S"`, the
/// nonterminal `S`, and the end-of-input marker `"$"` occupy distinct columns.
public enum TableKey: Hashable, CustomStringConvertible {
    /// A grammar terminal, including literal and pattern terminals.
    case terminal(Terminal)
    /// A grammar nonterminal.
    case nonTerminal(NonTerminal)
    /// The zero-width epsilon transition between NFA states.
    case epsilon
    /// The synthetic lookahead beyond the final input token.
    case endOfInput

    /// Creates the canonical table key for a grammar symbol.
    ///
    /// Epsilon spellings such as `ε`, `λ`, and the empty string all map to
    /// `.epsilon`; the grammar EOF meta-terminal maps to `.endOfInput`.
    /// EBNF meta-symbols have no parse-table columns and return `nil`.
    public init?(symbol: Symbol) {
        switch symbol {
        case .terminal(let terminal):
            self = tableKey(for: terminal)
        case .nonTerminal(let nonTerminal):
            self = .nonTerminal(nonTerminal)
        case .metaSymbol:
            return nil
        }
    }

    public var description: String {
        switch self {
        case .terminal(let terminal):
            return terminal.description
        case .nonTerminal(let nonTerminal):
            return nonTerminal.name
        case .epsilon:
            return MetaTerminal.eps.rawValue
        case .endOfInput:
            return MetaTerminal.eof.rawValue
        }
    }

    /// `Terminal` currently hashes regular expressions by object identity
    /// while comparing them by pattern. Hash terminal payloads structurally
    /// here so equal table keys always have equal hashes.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .terminal(let terminal):
            hasher.combine(0)
            switch terminal {
            case .string(let string):
                hasher.combine(0)
                hasher.combine(string)
            case .stringList(let list):
                hasher.combine(1)
                hasher.combine(list)
            case .characterRange(let range):
                hasher.combine(2)
                hasher.combine(range)
            case .regularExpression(let expression):
                hasher.combine(3)
                hasher.combine(expression.pattern)
            case .meta(let meta):
                hasher.combine(4)
                hasher.combine(meta)
            }
        case .nonTerminal(let nonTerminal):
            hasher.combine(1)
            hasher.combine(nonTerminal.name)
        case .epsilon:
            hasher.combine(2)
        case .endOfInput:
            hasher.combine(3)
        }
    }
}

/// Returns the canonical key for a terminal table column.
func tableKey(for terminal: Terminal) -> TableKey {
    if terminal.isEmpty {
        return .epsilon
    }
    if case .meta(.eof) = terminal {
        return .endOfInput
    }
    return .terminal(terminal)
}

/// Maps concrete token spellings to the terminal column that accepts them.
///
/// Exact literal terminals take precedence over pattern terminals. This makes
/// a grammar containing both `"if"` and an identifier regex deterministic.
struct TableKeyResolver {
    private let literalTerminals: Set<String>
    private let patternTerminals: [Terminal]

    init(grammar: Grammar) {
        literalTerminals = Set(grammar.terminals.compactMap { terminal in
            guard case .string(let string) = terminal, !string.isEmpty else {
                return nil
            }
            return string
        })
        patternTerminals = grammar.terminals.compactMap { terminal in
            switch terminal {
            case .characterRange, .stringList, .regularExpression:
                return terminal
            case .string, .meta:
                return nil
            }
        }
        .sorted { $0.description < $1.description }
    }

    func key(forToken token: String) -> TableKey {
        if literalTerminals.contains(token) {
            return .terminal(.string(string: token))
        }
        if let pattern = patternTerminals.first(where: {
            $0.matches(.string(string: token))
        }) {
            return .terminal(pattern)
        }
        return .terminal(.string(string: token))
    }
}
