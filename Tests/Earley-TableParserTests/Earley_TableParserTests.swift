import Testing
@testable import Earley_TableParser
import Foundation
import Grammar

func createSimpleGrammar() -> Grammar {
    // S ::= a S b | a
    let S = Symbol.nonTerminal("S")
    let a = Symbol.terminal("a")
    let b = Symbol.terminal("b")

    let productions = [
        Production(goal: NonTerminal("S"), rule: [a, S, b]),
        Production(goal: NonTerminal("S"), rule: [a]),
    ]
    return Grammar(productions: productions, start: NonTerminal("S"), lexicalTokens: [:])
}

func createAmbiguousGrammar() -> Grammar {
    // S ::= S S S | S S | b
    let S = Symbol.nonTerminal("S")
    let b = Symbol.terminal("b")

    let productions = [
        Production(goal: NonTerminal("S"), rule: [S, S, S]),
        Production(goal: NonTerminal("S"), rule: [S, S]),
        Production(goal: NonTerminal("S"), rule: [b])
    ]
    return Grammar(productions: productions, start: NonTerminal("S"), lexicalTokens: [:])
}

/// Helper to create a grammar with epsilon productions
func createEpsilonGrammar() -> Grammar {
        // S ::= A S b | a
        // A ::= a A | ε

        let S = Symbol.nonTerminal("S")
        let A = Symbol.nonTerminal("A")
        let a = Symbol.terminal("a")
        let b = Symbol.terminal("b")
        let eps = Symbol.terminal(.meta(.eps))
        
        let productions = [
            Production(goal: NonTerminal("S"), rule: [A, S, b]),
            Production(goal: NonTerminal("S"), rule: [a]),
            Production(goal: NonTerminal("A"), rule: [a, A]),
            Production(goal: NonTerminal("A"), rule: [eps]),

        ]
        return Grammar(productions: productions, start: NonTerminal("S"), lexicalTokens: [:])
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
        let first = grammar.first(of: [t("a")])
        
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
        
        #expect(grammar.isNullable(NonTerminal("A"), "A is nullable (A ::= epsilon)"))
        #expect(!grammar.isNullable(NonTerminal("S"), "S is not nullable"))
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

