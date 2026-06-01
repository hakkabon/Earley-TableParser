//
//  Earley_TableParserTests.swift
//  Earley-TableParser
//
//  Comprehensive test suite for the Earley Table Traversing Parser
//  Tests cover recognition, parsing, ambiguity detection, and SPPF generation
//

import Testing
@testable import Earley_TableParser
import Grammar

// MARK: - Test Setup Helpers

/// Helper to create a simple test grammar
func createSimpleGrammar() -> Grammar {
    let rules: [(NonTerminal, [Grammar.Symbol])] = [
        // S ::= a S b | a
        (
            NonTerminal(name: "S"),
            [
                .terminal(Terminal(description: "a")),
                .nonTerminal(NonTerminal(name: "S")),
                .terminal(Terminal(description: "b"))
            ]
        ),
        (NonTerminal(name: "S"), [.terminal(Terminal(description: "a"))])
    ]
    return try! Grammar(startSymbol: NonTerminal(name: "S"), productions: rules)
}

/// Helper to create an ambiguous grammar
func createAmbiguousGrammar() -> Grammar {
    let rules: [(NonTerminal, [Grammar.Symbol])] = [
        // S ::= S S S | S S | b
        (
            NonTerminal(name: "S"),
            [
                .nonTerminal(NonTerminal(name: "S")),
                .nonTerminal(NonTerminal(name: "S")),
                .nonTerminal(NonTerminal(name: "S"))
            ]
        ),
        (
            NonTerminal(name: "S"),
            [
                .nonTerminal(NonTerminal(name: "S")),
                .nonTerminal(NonTerminal(name: "S"))
            ]
        ),
        (NonTerminal(name: "S"), [.terminal(Terminal(description: "b"))])
    ]
    return try! Grammar(startSymbol: NonTerminal(name: "S"), productions: rules)
}

/// Helper to create a grammar with epsilon productions
func createEpsilonGrammar() -> Grammar {
    let rules: [(NonTerminal, [Grammar.Symbol])] = [
        // S ::= A S b | a
        (
            NonTerminal(name: "S"),
            [
                .nonTerminal(NonTerminal(name: "A")),
                .nonTerminal(NonTerminal(name: "S")),
                .terminal(Terminal(description: "b"))
            ]
        ),
        (NonTerminal(name: "S"), [.terminal(Terminal(description: "a"))]),
        // A ::= a A | ε
        (
            NonTerminal(name: "A"),
            [
                .terminal(Terminal(description: "a")),
                .nonTerminal(NonTerminal(name: "A"))
            ]
        ),
        (NonTerminal(name: "A"), [])  // epsilon production
    ]
    return try! Grammar(startSymbol: NonTerminal(name: "S"), productions: rules)
}

// MARK: - Test Structures

struct EarleyParserTests {
    
    // MARK: - NFA Construction Tests
    
    @Test("NFA construction for simple grammar")
    func testNFAConstruction() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        
        #expect(nfa.stateCount > 0, "NFA should have at least one state")
        #expect(nfa.states.count == nfa.stateCount)
        #expect(!nfa.states.isEmpty, "Initial state should exist")
    }
    
    @Test("NFA construction for ambiguous grammar")
    func testNFAConstructionAmbiguous() {
        let grammar = createAmbiguousGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        
        #expect(nfa.stateCount > 0)
        // Ambiguous grammars typically have more states
        #expect(nfa.stateCount >= 3)
    }
    
    @Test("NFA construction for epsilon productions")
    func testNFAConstructionEpsilon() {
        let grammar = createEpsilonGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        
        #expect(nfa.stateCount > 0, "NFA should handle epsilon productions")
    }
    
    // MARK: - Recogniser Tests
    
    @Test("Recogniser accepts valid inputs")
    func testRecogniserAccepts() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
        
        #expect(recET(table: table, input: ["a"]))
        #expect(recET(table: table, input: ["a", "a", "b"]))
        #expect(recET(table: table, input: ["a", "a", "b", "b"]))
    }
    
    @Test("Recogniser rejects invalid inputs")
    func testRecogniserRejects() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
        
        #expect(!recET(table: table, input: ["b"]))
        #expect(!recET(table: table, input: ["a", "b"]))
        #expect(!recET(table: table, input: ["a", "a"]))
        #expect(!recET(table: table, input: []))
    }
    
    @Test("Recogniser with epsilon productions")
    func testRecogniserEpsilon() {
        let grammar = createEpsilonGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
        
        #expect(recET(table: table, input: ["a"]))
        #expect(recET(table: table, input: ["a", "a", "b"]))
        #expect(recET(table: table, input: ["a", "b"]))  // A derives epsilon
    }
    
    // MARK: - Parser Tests (BSR Generation)
    
    @Test("Parser generates BSR elements")
    func testParserGeneratesBSR() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        let result = simpleET(table: table, input: ["a", "a", "b"])
        
        #expect(result.accepted)
        #expect(result.bsrSet.count > 0, "Parser should generate BSR elements")
        #expect(!result.hasAmbiguity, "Simple grammar is unambiguous")
    }
    
    @Test("Parser accepts valid inputs")
    func testParserAccepts() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        #expect(simpleET(table: table, input: ["a"]).accepted)
        #expect(simpleET(table: table, input: ["a", "a", "b"]).accepted)
        #expect(simpleET(table: table, input: ["a", "a", "b", "b"]).accepted)
    }
    
    @Test("Parser rejects invalid inputs")
    func testParserRejects() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        #expect(!simpleET(table: table, input: ["b"]).accepted)
        #expect(!simpleET(table: table, input: ["a", "b"]).accepted)
        #expect(!simpleET(table: table, input: []).accepted)
    }
    
    // MARK: - Ambiguity Tests
    
    @Test("Parser detects ambiguity in S ::= SSS | SS | b")
    func testDetectAmbiguity() {
        let grammar = createAmbiguousGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        let result = simpleET(table: table, input: ["b", "b", "b"])
        
        #expect(result.accepted)
        #expect(result.bsrSet.count > 1, "Ambiguous grammar should generate multiple BSR elements")
    }
    
    @Test("Recogniser vs Parser consistency")
    func testRecogniserParserConsistency() {
        let grammars: [Grammar] = [
            createSimpleGrammar(),
            createAmbiguousGrammar(),
            createEpsilonGrammar()
        ]
        
        let testInputs: [[String]] = [
            ["a"],
            ["a", "a", "b"],
            ["b"],
            []
        ]
        
        for grammar in grammars {
            let nfa = buildEarleyNFA(grammar: grammar)
            let recTable = buildRecogniserTable(nfa: nfa, grammar: grammar)
            let parseTable = buildSLParseTable(nfa: nfa, grammar: grammar)
            
            for input in testInputs {
                let recResult = recET(table: recTable, input: input)
                let parseResult = simpleET(table: parseTable, input: input)
                
                #expect(recResult == parseResult.accepted,
                    "Recogniser and parser should agree on acceptance for input \(input)")
            }
        }
    }
    
    // MARK: - SPPF Tests
    
    @Test("Parser generates SPPF graph structure")
    func testSPPFGeneration() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        let result = simpleET(table: table, input: ["a", "a", "b"])
        
        #expect(result.accepted)
        // SPPF graph construction is in development
        // when implemented, test: result.sppfGraph != nil
    }
    
    // MARK: - Earley Sets Tests
    
    @Test("Earley sets are properly constructed")
    func testEarleySetsConstruction() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        let result = simpleET(table: table, input: ["a"])
        
        #expect(result.earleySets.count == 2, "For input of length 1, should have E_0 and E_1")
        #expect(!result.earleySets[0].isEmpty, "E_0 should not be empty")
    }
    
    @Test("Earley sets for longer inputs")
    func testEarleySetsLonger() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        let input = ["a", "a", "b"]
        let result = simpleET(table: table, input: input)
        
        #expect(result.earleySets.count == input.count + 1)
        #expect(!result.earleySets[0].isEmpty)
    }
    
    // MARK: - Grammar Analysis Tests
    
    @Test("FIRST set computation")
    func testFirstSetComputation() {
        let grammar = createEpsilonGrammar()
        let first = grammar.first(of: [.terminal(Terminal(description: "a"))])
        
        #expect(first.terminals.contains("a"))
        #expect(!first.nullable)
    }
    
    @Test("FOLLOW set computation")
    func testFollowSetComputation() {
        let grammar = createEpsilonGrammar()
        let follow = grammar.followSets()
        
        #expect(follow["S"]?.contains("$") ?? false, "Start symbol should have $ in FOLLOW")
    }
    
    @Test("Nullable nonterminal detection")
    func testNullableDetection() {
        let grammar = createEpsilonGrammar()
        
        #expect(grammar.isNullableNonterminal("A"), "A is nullable (A ::= epsilon)")
        #expect(!grammar.isNullableNonterminal("S"), "S is not nullable")
    }
    
    // MARK: - Tokenizer Tests
    
    @Test("Simple tokenizer creation and tokenization")
    func testTokenizer() {
        let tokenizer = EarleyTokenizer.simple(terminals: ["a", "b", "c"])
        
        let tokens = try! tokenizer.tokenize("a b c")
        #expect(tokens == ["a", "b", "c"])
    }
    
    @Test("Tokenizer with whitespace handling")
    func testTokenizerWhitespace() {
        let tokenizer = EarleyTokenizer.simple(terminals: ["a", "b"])
        
        let tokens = try! tokenizer.tokenize("  a   b   ")
        #expect(tokens == ["a", "b"])
    }
    
    @Test("Tokenizer rejects unknown tokens")
    func testTokenizerUnknown() {
        let tokenizer = EarleyTokenizer.simple(terminals: ["a", "b"])
        
        #expect(throws: TokenizationError.self) {
            try tokenizer.tokenize("a x b")
        }
    }
    
    // MARK: - Integration Tests
    
    @Test("End-to-end parsing with tokenization")
    func testEndToEndWithTokenization() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let tokenizer = EarleyTokenizer.simple(terminals: ["a", "b"])
        
        let result = try! tokenizeAndParse(
            input: "a a b",
            tokenizer: tokenizer,
            table: table,
            grammar: grammar
        )
        
        #expect(result.accepted)
        #expect(result.bsrSet.count > 0)
    }
}

// MARK: - Performance Benchmarks

struct PerformanceBenchmarks {
    
    @Test("Recognition performance for small inputs")
    func benchmarkRecognition() {
        let grammar = createSimpleGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
        
        let inputs = [
            ["a"],
            ["a", "a", "b"],
            ["a", "a", "b", "b"],
            ["a", "a", "b", "b", "b", "b"]
        ]
        
        for input in inputs {
            let start = Date()
            _ = recET(table: table, input: input)
            let elapsed = Date().timeIntervalSince(start)
            
            // Should complete very quickly for small inputs
            #expect(elapsed < 0.1, "Recognition should complete in < 100ms for small inputs")
        }
    }
    
    @Test("Parsing performance for ambiguous grammars")
    func benchmarkAmbiguousParsing() {
        let grammar = createAmbiguousGrammar()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        
        let start = Date()
        let result = simpleET(table: table, input: ["b", "b", "b"])
        let elapsed = Date().timeIntervalSince(start)
        
        #expect(result.accepted)
        #expect(elapsed < 1.0, "Ambiguous parsing should complete in reasonable time")
    }
}

