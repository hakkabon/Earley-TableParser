// ParserTokenizer.swift
// Tokenization layer for the Earley parser supporting both simple and regex-based tokenization

import Foundation
import Grammar

// MARK: - Token Definition

/// Defines how to tokenize input
public struct TokenRule {
    public let name: String
    public let pattern: String  // regex or literal string
    public let isRegex: Bool
    
    public init(name: String, literal: String) {
        self.name = name
        self.pattern = literal
        self.isRegex = false
    }
    
    public init(name: String, regex: String) {
        self.name = name
        self.pattern = regex
        self.isRegex = true
    }
}

// MARK: - Tokenizer Implementation

/// Tokenizes input strings into token sequences
public class EarleyTokenizer {
    private let rules: [TokenRule]
    private let skipWhitespace: Bool
    
    public init(rules: [TokenRule], skipWhitespace: Bool = true) {
        self.rules = rules
        self.skipWhitespace = skipWhitespace
    }
    
    /// Create a simple tokenizer that splits on whitespace and recognizes specific tokens
    public static func simple(terminals: [String]) -> EarleyTokenizer {
        let rules = terminals.map { TokenRule(name: $0, literal: $0) }
        return EarleyTokenizer(rules: rules, skipWhitespace: true)
    }
    
    /// Tokenize input using the configured rules
    public func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var pos = 0
        let chars = Array(input)
        
        while pos < chars.count {
            // Skip whitespace if configured
            if skipWhitespace {
                while pos < chars.count && chars[pos].isWhitespace {
                    pos += 1
                }
            }
            
            if pos >= chars.count { break }
            
            // Try to match a token rule
            var matched = false
            let remaining = String(chars[pos...])
            
            for rule in rules {
                let (success, token, length) = matchRule(rule, in: remaining)
                if success {
                    tokens.append(token)
                    pos += length
                    matched = true
                    break
                }
            }
            
            if !matched {
                let context = String(chars[pos...]).prefix(20)
                throw TokenizationError.unknownToken(position: pos, character: String(chars[pos]), context: String(context))
            }
        }
        
        return tokens
    }
    
    private func matchRule(_ rule: TokenRule, in text: String) -> (success: Bool, token: String, length: Int) {
        if rule.isRegex {
            do {
                let regex = try NSRegularExpression(pattern: "^\(rule.pattern)")
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let matchedRange = match.range
                    if let range = Range(matchedRange, in: text) {
                        let matched = String(text[range])
                        return (true, rule.name, matched.count)
                    }
                }
            } catch {
                return (false, "", 0)
            }
        } else {
            if text.hasPrefix(rule.pattern) {
                return (true, rule.name, rule.pattern.count)
            }
        }
        
        return (false, "", 0)
    }
}

/// Errors that can occur during tokenization
public enum TokenizationError: Error, CustomStringConvertible {
    case unknownToken(position: Int, character: String, context: String)
    case emptyInput
    
    public var description: String {
        switch self {
        case .unknownToken(let pos, let char, let ctx):
            return "Unknown token at position \(pos): '\(char)' in context '\(ctx)'"
        case .emptyInput:
            return "Empty input string"
        }
    }
}

// MARK: - Extended Earley Parser with Tokenization

/// Parser that combines tokenization and parsing
public func tokenizeAndParse(
    input: String,
    tokenizer: EarleyTokenizer,
    table: SLParseTable,
    grammar: Grammar
) throws -> ParseResult {
    guard !input.isEmpty else {
        return ParseResult(accepted: false, bsrSet: [], earleySets: [], sppfGraph: nil)
    }
    
    let tokens = try tokenizer.tokenize(input)
    return simpleET(table: table, input: tokens)
}
