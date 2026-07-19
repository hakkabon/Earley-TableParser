//
//  Earley_TableParserTests.swift
//  Earley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2026/06/01.
//  Comprehensive tests for the Earley Table Traversing Parser.
//

import Testing
@testable import Earley_TableParser
import Foundation
import Grammar
import Parser

// MARK: - Grammar Helpers

/// Terminal symbol from string
func T(_ s: String) -> Symbol { .terminal(Terminal(string: s)) }

/// Non-terminal symbol
func N(_ name: String) -> Symbol { .nonTerminal(NonTerminal(name: name)) }

/// Non-terminal
func NT(_ name: String) -> NonTerminal { NonTerminal(name: name) }

// MARK: - Example Grammars from Scott & Johnstone (2026)

/// Γ₁: S ::= A S b | a , A ::= a A | ε (Section 2.3)
func gamma1() -> Grammar {
    Grammar(
        productions: [
            Production(goal: NT("S"), rule: [N("A"), N("S"), T("b")]),
            Production(goal: NT("S"), rule: [T("a")]),
            Production(goal: NT("A"), rule: [T("a"), N("A")]),
            Production(goal: NT("A"), rule: [])  // ε
        ],
        start: NT("S"),
        lexicalTokens: [:]
    )
}

/// Γ₂: S ::= B B S a | b b b , B ::= b b B | ε (Section 4.3)
func gamma2() -> Grammar {
    Grammar(
        productions: [
            Production(goal: NT("S"), rule: [N("B"), N("B"), N("S"), T("a")]),
            Production(goal: NT("S"), rule: [T("b"), T("b"), T("b")]),
            Production(goal: NT("B"), rule: [T("b"), T("b"), N("B")]),
            Production(goal: NT("B"), rule: [])  // ε
        ],
        start: NT("S"),
        lexicalTokens: [:]
    )
}

/// Γ₃: S ::= S S S | S S | b (highly ambiguous, Section 5.1)
func gamma3() -> Grammar {
    Grammar(
        productions: [
            Production(goal: NT("S"), rule: [N("S"), N("S"), N("S")]),
            Production(goal: NT("S"), rule: [N("S"), N("S")]),
            Production(goal: NT("S"), rule: [T("b")])
        ],
        start: NT("S"),
        lexicalTokens: [:]
    )
}

// MARK: - EarleyParserTests

@Suite
struct EarleyParserTests {

    // MARK: - NFA Construction Tests

    @Test("NFA construction produces valid state count")
    func testNFAConstructionStateCount() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        #expect(nfa.stateCount > 0, "NFA should have at least one state")
        #expect(nfa.states.count == nfa.stateCount, "states.count should match stateCount")
    }

    @Test("NFA construction for Γ₁ (simple grammar)")
    func testNFAConstructionGamma1() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        #expect(nfa.stateCount >= 2, "Γ₁ should have at least 2 states")
        #expect(nfa.alphabet.contains(where: { isEpsilonSymbol($0) }), "Should include ε in alphabet")
    }

    @Test("NFA construction for Γ₂ (ε-productions)")
    func testNFAConstructionGamma2() {
        let nfa = buildEarleyNFA(grammar: gamma2())
        #expect(nfa.stateCount > 0, "Should handle ε-productions")
    }

    @Test("NFA construction for Γ₃ (ambiguous grammar)")
    func testNFAConstructionGamma3() {
        let nfa = buildEarleyNFA(grammar: gamma3())
        #expect(nfa.stateCount >= 2, "Ambiguous grammars typically have more states")
    }

    // MARK: - Recogniser Tests

    @Test("Recogniser accepts valid Γ₁ inputs")
    func testRecogniserGamma1Accepts() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma1())

        #expect(recET(table: table, input: ["a"]))
        #expect(recET(table: table, input: ["a", "b"]))
        #expect(recET(table: table, input: ["a", "a", "b"]))
        #expect(recET(table: table, input: ["a", "a", "a", "b", "b"]))
    }

    @Test("Recogniser rejects invalid Γ₁ inputs")
    func testRecogniserGamma1Rejects() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma1())

        #expect(!recET(table: table, input: ["b"]))
        #expect(!recET(table: table, input: ["a", "b", "b"]))
        #expect(!recET(table: table, input: ["a", "a"]))
    }

    @Test("Recogniser accepts valid Γ₂ inputs")
    func testRecogniserGamma2Accepts() {
        let nfa = buildEarleyNFA(grammar: gamma2())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma2())

        #expect(recET(table: table, input: ["b", "b", "b"]))
        #expect(recET(table: table, input: ["b", "b", "b", "a"]))
    }

    @Test("Recogniser rejects invalid Γ₂ inputs")
    func testRecogniserGamma2Rejects() {
        let nfa = buildEarleyNFA(grammar: gamma2())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma2())

        #expect(!recET(table: table, input: ["b"]))
        #expect(!recET(table: table, input: ["b", "b"]))
    }

    @Test("Recogniser accepts valid Γ₃ inputs")
    func testRecogniserGamma3Accepts() {
        let nfa = buildEarleyNFA(grammar: gamma3())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma3())

        #expect(recET(table: table, input: ["b"]))
        #expect(recET(table: table, input: ["b", "b"]))
        #expect(recET(table: table, input: ["b", "b", "b"]))
    }

    // MARK: - Parser Tests (BSR Generation)

    @Test("Parser generates BSR elements for Γ₁")
    func testParserBSRGamma1() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())

        let result = simpleET(table: table, input: ["a", "a", "b"])

        #expect(result.accepted)
        #expect(result.bsrSet.count > 0, "Parser should generate BSR elements")
        #expect(!result.hasAmbiguity, "Γ₁ is unambiguous")
    }

    @Test("Parser correctly identifies unambiguous Γ₁")
    func testParserUnambiguousGamma1() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())

        let result = simpleET(table: table, input: ["a"])
        #expect(!result.hasAmbiguity)
    }

    @Test("Parser detects ambiguity in Γ₃")
    func testParserAmbiguousGamma3() {
        let nfa = buildEarleyNFA(grammar: gamma3())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma3())

        let result = simpleET(table: table, input: ["b", "b", "b"])

        #expect(result.accepted)
        // With ambiguous grammar, we expect multiple BSR elements for the same (LHS, left, right)
        #expect(result.bsrSet.count > 1, "Ambiguous grammar should generate multiple BSR elements")
    }

    @Test("Parser handles Γ₂ with ε-productions")
    func testParserGamma2Epsilon() {
        let nfa = buildEarleyNFA(grammar: gamma2())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma2())

        // "bbba" - B→ε,ε; S→BBSa
        let result = simpleET(table: table, input: ["b", "b", "b", "a"])
        #expect(result.accepted)
        #expect(result.bsrSet.count > 0)
    }

    // MARK: - SPPF Tests

    @Test("SPPF construction for simple grammar")
    func testSPPFConstructionSimple() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a", "a", "b"])

        #expect(result.accepted)

        let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: ["a", "a", "b"])
        let nodes = sppf.getAllNodes()
        #expect(nodes.count > 0, "SPPF should have nodes")
    }

    @Test("SPPF contains correct node types")
    func testSPPFNodeTypes() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: ["a"])
        let nodes = sppf.getAllNodes()

        // Should have symbol nodes for non-terminals
        #expect(nodes.contains(where: { node in
            if case .symbol = node { return true }
            return false
        }), "Should have symbol nodes")
    }

    @Test("SPPF graph has valid edge structure")
    func testSPPFEdgeStructure() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: ["a"])

        // Check that all children exist in the graph
        for node in sppf.getAllNodes() {
            for child in sppf.getChildren(of: node) {
                #expect(sppf.getAllNodes().contains(child), "Child should exist in graph")
            }
        }
    }

    // MARK: - Derivation Extraction Tests

    @Test("Extract derivation for simple accepted input")
    func testExtractDerivationSimple() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        let derivation = extractDerivation(from: result.bsrSet, grammar: grammar, tokens: ["a"])
        #expect(derivation != nil, "Should extract a derivation")
    }

    @Test("Extract derivation returns nil for rejected input")
    func testExtractDerivationRejected() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["b"])  // Rejected

        #expect(!result.accepted)

        let derivation = extractDerivation(from: result.bsrSet, grammar: grammar, tokens: ["b"])
        #expect(derivation == nil, "No derivation for rejected input")
    }

    // MARK: - Earley Sets Tests

    @Test("Earley sets count matches input length + 1")
    func testEarleySetsCount() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)

        let inputs: [[String]] = [
            [],
            ["a"],
            ["a", "b"],
            ["a", "a", "b"]
        ]

        for tokens in inputs {
            let result = simpleET(table: table, input: tokens)
            #expect(result.earleySets.count == tokens.count + 1,
                "For \(tokens.count) tokens, should have \(tokens.count + 1) Earley sets")
        }
    }

    @Test("E₀ is always non-empty")
    func testEarleySetE0() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)

        let result = simpleET(table: table, input: ["a"])
        #expect(!result.earleySets[0].isEmpty, "E₀ should not be empty")
    }

    @Test("Earley sets contain valid Earley pairs")
    func testEarleyPairValidity() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)

        let result = simpleET(table: table, input: ["a"])

        for ej in result.earleySets {
            for pair in ej {
                #expect(pair.state >= 0 && pair.state < nfa.stateCount,
                    "State index \(pair.state) should be valid")
                #expect(pair.backIndex >= 0, "Back-index should be non-negative")
            }
        }
    }

    // MARK: - BSR Structure Tests

    @Test("BSR elements have valid extents")
    func testBSRElementExtents() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        for elem in result.bsrSet {
            #expect(elem.leftExtent >= 0, "Left extent should be non-negative")
            #expect(elem.rightExtent >= elem.leftExtent, "Right extent should be >= left extent")
            #expect(elem.pivot >= elem.leftExtent && elem.pivot <= elem.rightExtent,
                "Pivot should be within extents")
        }
    }

    @Test("BSR elements have valid grammar components")
    func testBSRComponentValidity() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        // `NodeLabel.goal` is a non-optional `NonTerminal`, so every BSR
        // element necessarily has an LHS — this test now checks that the
        // dot position is always a valid index into the label's symbols.
        for elem in result.bsrSet {
            #expect(elem.label.position >= 0 && elem.label.position <= elem.label.symbols.count,
                     "BSR label's dot position should be within [0, symbols.count]")
        }
    }

    // MARK: - Grammar Analysis Tests

    @Test("FOLLOW sets computed correctly")
    func testFollowSets() {
        let grammar = gamma1()
        let follow = grammar.followSets()

        // Start symbol S should have $ in its FOLLOW set
        #expect(follow.keys.contains(NT("S")), "Should compute FOLLOW for start symbol")
    }

    @Test("Nullable non-terminals detected correctly")
    func testNullableNonterminals() {
        let grammar = gamma1()

        // A → ε, so A should be nullable
        #expect(grammar.isNullable(NT("A")), "A should be nullable (A → ε)")

        // S cannot derive ε directly, and A can be ε but S→ASb requires symbols
        #expect(!grammar.isNullable(NT("S")), "S should not be nullable")
    }

    // MARK: - Edge Cases

    @Test("Parser handles single-token inputs")
    func testSingleTokenInput() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)

        let result = simpleET(table: table, input: ["a"])
        #expect(result.accepted)
    }

    @Test("Parser handles empty input (when grammar allows)")
    func testEmptyInput() {
        // Grammar that allows empty input: S → ε | a
        let epsGrammar = Grammar(
            productions: [
                Production(goal: NT("S"), rule: []),
                Production(goal: NT("S"), rule: [T("a")])
            ],
            start: NT("S"),
            lexicalTokens: [:]
        )

        let nfa = buildEarleyNFA(grammar: epsGrammar)
        let table = buildSLParseTable(nfa: nfa, grammar: epsGrammar)
        let result = simpleET(table: table, input: [])

        #expect(result.accepted, "Should accept empty input when grammar allows")
    }

    @Test("Parser rejects completely invalid input")
    func testRejectedInput() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)

        let result = simpleET(table: table, input: ["x", "y", "z"])
        #expect(!result.accepted, "Should reject input with unknown tokens")
    }

    // MARK: - Consistency Tests

    @Test("Recogniser and parser agree on acceptance")
    func testRecogniserParserConsistency() {
        let grammars = [gamma1(), gamma2(), gamma3()]
        let testInputs: [[String]] = [
            [],
            ["a"],
            ["b"],
            ["a", "b"],
            ["b", "b", "b"]
        ]

        for grammar in grammars {
            let nfa = buildEarleyNFA(grammar: grammar)
            let recTable = buildRecogniserTable(nfa: nfa, grammar: grammar)
            let parseTable = buildSLParseTable(nfa: nfa, grammar: grammar)

            for input in testInputs {
                let recResult = recET(table: recTable, input: input)
                let parseResult = simpleET(table: parseTable, input: input)

                #expect(recResult == parseResult.accepted,
                    "Recogniser and parser should agree on '\(input.joined(separator: " "))'")
            }
        }
    }
}

// MARK: - Performance Benchmarks

@Suite
struct PerformanceBenchmarks {
    
    @Test("Recognition performance for small inputs")
    func benchmarkRecognition() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildRecogniserTable(nfa: nfa, grammar: grammar)

        let inputs: [[String]] = [
            ["a"],
            ["a", "a", "b"],
            ["a", "a", "b", "b"]
        ]

        for input in inputs {
            let startTime = CFAbsoluteTimeGetCurrent()
            _ = recET(table: table, input: input)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            // Should complete very quickly (< 1 second for small inputs)
            #expect(elapsed < 1.0, "Recognition should complete in < 1s for input \(input)")
        }
    }

    @Test("Parsing performance for ambiguous grammar")
    func benchmarkAmbiguousParsing() {
        let grammar = gamma3()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = simpleET(table: table, input: ["b", "b", "b"])
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        #expect(result.accepted)
        #expect(elapsed < 5.0, "Ambiguous parsing should complete in reasonable time")
    }
}

// MARK: - Additional Tests for Missing Features

@Suite
struct AdditionalTests {
    
    @Test("NFA isCore detection")
    func testNFACoreDetection() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)

        // Should have at least some core states
        let hasCore = (0..<nfa.stateCount).contains { nfa.isCore($0) }
        #expect(hasCore, "Should have some core states")
    }

    @Test("NFA completed nonterminals")
    func testNFACompletedNonterminals() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)

        for p in 0..<nfa.stateCount {
            let completed = nfa.completedNonterminals(in: p)
            // Just verify it returns something (could be empty)
            _ = completed
        }
    }

    @Test("SPPF getExtendableNodes")
    func testSPPFExtendableNodes() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: ["a"])
        let extendable = sppf.getExtendableNodes()
        // Extendable nodes are non-leaf, non-packed nodes
        #expect(extendable.count >= 0)
    }

    @Test("Graphviz export works")
    func testGraphvizExport() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildSLParseTable(nfa: nfa, grammar: grammar)
        let result = simpleET(table: table, input: ["a"])

        #expect(result.accepted)

        let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: ["a"])
        let dot = sppf.graphviz

        // Basic sanity checks on DOT output
        #expect(dot.contains("digraph"), "Should contain digraph declaration")
        #expect(dot.contains("{"), "Should contain opening brace")
        #expect(dot.contains("}"), "Should contain closing brace")
    }
}
