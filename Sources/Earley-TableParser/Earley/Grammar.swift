// Grammar.swift
// Extensions for the external Grammar package used in NFA and parser table construction.

import Foundation
import Grammar

// MARK: - Grammar Extensions

extension Grammar {
    
    /// Check if a nonterminal can derive ε
    public func isNullableNonterminal(_ name: String) -> Bool {
        var nullable = Set<String>()
        var changed = true
        
        while changed {
            changed = false
            for rule in productions {
                let ntName = rule.lhs.name
                if nullable.contains(ntName) { continue }
                
                let allNull = rule.rhs.allSatisfy { sym in
                    switch sym {
                    case .terminal:
                        return false
                    case .nonTerminal(let nt):
                        return nullable.contains(nt.name)
                    case .metaSymbol:
                        return false
                    }
                }
                
                if allNull {
                    nullable.insert(ntName)
                    changed = true
                }
            }
        }
        
        return nullable.contains(name)
    }
    
    /// Check if a sequence of symbols can derive ε
    public func isNullable(_ symbols: [Symbol]) -> Bool {
        symbols.allSatisfy { symbol in
            switch symbol {
            case .terminal:
                return false
            case .nonTerminal(let nt):
                return isNullableNonterminal(nt.name)
            case .metaSymbol:
                return false
            }
        }
    }
    
    /// Compute FIRST set of a symbol sequence
    public func first(of symbols: [Symbol]) -> (terminals: Set<String>, nullable: Bool) {
        var result = Set<String>()
        
        for symbol in symbols {
            switch symbol {
            case .terminal(let term):
                result.insert(term.description)
                return (result, false)
            case .nonTerminal(let nt):
                let (firstSet, nullable) = firstOfNonterminal(nt.name)
                result.formUnion(firstSet)
                if !nullable { return (result, false) }
            case .metaSymbol(let meta):
                result.insert(meta)
                return (result, false)
            }
        }
        
        return (result, true)
    }
    
    /// Compute FIRST set of a nonterminal
    private func firstOfNonterminal(_ name: String) -> (Set<String>, Bool) {
        var firstSets: [String: Set<String>] = [:]
        var nullable = Set<String>()
        
        // Compute nullable nonterminals first
        var changed = true
        while changed {
            changed = false
            for rule in productions {
                let lhsName = rule.lhs.name
                if nullable.contains(lhsName) { continue }
                
                let allNull = rule.rhs.allSatisfy { sym in
                    switch sym {
                    case .terminal:
                        return false
                    case .nonTerminal(let nt):
                        return nullable.contains(nt.name)
                    case .metaSymbol:
                        return false
                    }
                }
                
                if allNull {
                    nullable.insert(lhsName)
                    changed = true
                }
            }
        }
        
        // Compute FIRST sets
        changed = true
        while changed {
            changed = false
            for rule in productions {
                let lhsName = rule.lhs.name
                
                for sym in rule.rhs {
                    switch sym {
                    case .terminal(let term):
                        if firstSets[lhsName, default: []].insert(term.description).inserted {
                            changed = true
                        }
                        break
                    case .nonTerminal(let nt):
                        let ntName = nt.name
                        let symbolFirst = firstSets[ntName, default: []]
                        for term in symbolFirst {
                            if firstSets[lhsName, default: []].insert(term).inserted {
                                changed = true
                            }
                        }
                        if !nullable.contains(ntName) { break }
                    case .metaSymbol(let meta):
                        if firstSets[lhsName, default: []].insert(meta).inserted {
                            changed = true
                        }
                        break
                    }
                }
            }
        }
        
        return (firstSets[name, default: []], nullable.contains(name))
    }
    
    /// Compute FOLLOW sets for all nonterminals
    public func followSets() -> [String: Set<String>] {
        var follow: [String: Set<String>] = [:]
        follow[startSymbol.name] = ["$"]
        
        var changed = true
        while changed {
            changed = false
            
            for rule in productions {
                let lhs = rule.lhs.name
                
                for (i, sym) in rule.rhs.enumerated() {
                    guard case .nonTerminal(let nt) = sym else { continue }
                    let ntName = nt.name
                    
                    let symbolsAfter = Array(rule.rhs.dropFirst(i + 1))
                    let (firstSet, canBeNull) = first(of: symbolsAfter)
                    
                    for term in firstSet {
                        if follow[ntName, default: []].insert(term).inserted {
                            changed = true
                        }
                    }
                    
                    if canBeNull {
                        if let followOfLhs = follow[lhs] {
                            for term in followOfLhs {
                                if follow[ntName, default: []].insert(term).inserted {
                                    changed = true
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return follow
    }
    
    /// Get all terminal symbols used in the grammar
    public var terminals: Set<String> {
        var result = Set<String>()
        for rule in productions {
            for sym in rule.rhs {
                switch sym {
                case .terminal(let term):
                    result.insert(term.description)
                case .nonTerminal:
                    break
                case .metaSymbol(let meta):
                    result.insert(meta)
                }
            }
        }
        return result
    }
    
    /// Get all nonterminal symbols used in the grammar
    public var nonterminals: Set<String> {
        var result = Set<String>()
        for rule in productions {
            result.insert(rule.lhs.name)
        }
        return result
    }
}
