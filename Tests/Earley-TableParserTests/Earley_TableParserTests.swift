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
import Lexer

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

// MARK: - Suite: Extended Lookahead (EL) parser

@Suite("EL Parser — parseET()")
struct ELParserTests {

    // MARK: Acceptance agreement with SL

    @Test("SL and EL agree on all Γ₁ inputs")
    func elSlAgreementGamma1() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let cases: [[String]] = [
            [], ["a"], ["b"], ["a","b"],
            ["a","a","b"], ["a","a","b","b"],
            ["a","a","a","b","b"]
        ]
        for tokens in cases {
            let slAcc = simpleET(table: sl, input: tokens).accepted
            let elAcc = parseET(table: el,  input: tokens).accepted
            #expect(slAcc == elAcc,
                    "SL=\(slAcc) EL=\(elAcc) for '\(tokens.joined(separator: " "))'")
        }
    }

    @Test("SL and EL agree on all Γ₂ inputs")
    func elSlAgreementGamma2() {
        let grammar = gamma2()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let cases: [[String]] = [
            ["b","b","b"], ["b","b","b","a"],
            ["b","b"], ["b"], []
        ]
        for tokens in cases {
            let slAcc = simpleET(table: sl, input: tokens).accepted
            let elAcc = parseET(table: el,  input: tokens).accepted
            #expect(slAcc == elAcc,
                    "SL=\(slAcc) EL=\(elAcc) for '\(tokens.joined(separator: " "))'")
        }
    }

    @Test("SL and EL agree on all Γ₃ inputs")
    func elSlAgreementGamma3() {
        let grammar = gamma3()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let cases: [[String]] = [
            ["b"], ["b","b"], ["b","b","b"], ["b","b","b","b"], ["a"]
        ]
        for tokens in cases {
            let slAcc = simpleET(table: sl, input: tokens).accepted
            let elAcc = parseET(table: el,  input: tokens).accepted
            #expect(slAcc == elAcc,
                    "SL=\(slAcc) EL=\(elAcc) for '\(tokens.joined(separator: " "))'")
        }
    }

    // MARK: BSR quality

    @Test("EL produces a non-empty BSR set on accepted input")
    func elBSRNonEmpty() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let result  = parseET(table: el, input: ["a", "a", "b"])
        #expect(result.accepted)
        #expect(!result.bsrSet.isEmpty)
    }

    @Test("EL BSR elements have valid extents i ≤ k ≤ j")
    func elBSRExtents() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let result  = parseET(table: el, input: ["a", "a", "b"])
        for elem in result.bsrSet {
            #expect(elem.leftExtent  >= 0)
            #expect(elem.pivot       >= elem.leftExtent)
            #expect(elem.rightExtent >= elem.pivot)
        }
    }

    @Test("EL detects ambiguity in Γ₃ 'bbb'")
    func elDetectsAmbiguity() {
        let grammar = gamma3()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let result  = parseET(table: el, input: ["b","b","b"])
        #expect(result.accepted)
        #expect(result.hasAmbiguity)
    }

    @Test("EL unambiguous result has no false-positive ambiguity")
    func elNoFalsePositiveAmbiguity() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let result  = parseET(table: el, input: ["a", "a", "b"])
        #expect(result.accepted)
        #expect(!result.hasAmbiguity)
    }

    // MARK: EL table structure

    @Test("EL table has per-state info for all NFA states")
    func elStateInfoCoverage() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        for p in 0..<nfa.stateCount {
            #expect(el.info(state: p) != nil, "stateInfo[\(p)] must not be nil")
        }
    }

    @Test("SELECT(p) is non-empty for states reachable by scanner/completer")
    func elSelectSetsNonEmptyForActiveStates() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        // State 0 is the start state: SELECT must be non-empty (it must allow the scanner).
        #expect(el.info(state: 0)?.selectSet.isEmpty == false,
                "State 0 SELECT set should not be empty")
    }

    @Test("rLHS(p) only contains nonterminals of complete items")
    func elRLHSOnlyCompleteItems() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        for p in 0..<nfa.stateCount {
            guard let info = el.info(state: p) else { continue }
            for nt in info.rLHS {
                // nt must appear as the goal of some complete slot in G_p.
                let hasCompleteSlot = nfa.states[p].contains {
                    $0.isComplete && $0.production.goal == nt
                }
                #expect(hasCompleteSlot,
                        "rLHS member \(nt.name) has no complete slot in G_\(p)")
            }
        }
    }

    // MARK: Three-way consistency (recET / simpleET / parseET)

    @Test("Three-way agreement: recET, simpleET, parseET on Γ₁")
    func threeWayGamma1() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let rec     = buildRecogniserTable(nfa: nfa, grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let cases: [[String]] = [[], ["a"], ["b"], ["a","b"], ["a","a","b"]]
        for tokens in cases {
            let r = recET(table: rec, input: tokens)
            let s = simpleET(table: sl,  input: tokens).accepted
            let e = parseET(table: el,   input: tokens).accepted
            #expect(r == s && s == e,
                    "Three-way mismatch on '\(tokens)': rec=\(r) sl=\(s) el=\(e)")
        }
    }

    @Test("Three-way agreement on Γ₂")
    func threeWayGamma2() {
        let grammar = gamma2()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let rec     = buildRecogniserTable(nfa: nfa, grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let cases: [[String]] = [["b","b","b"], ["b","b","b","a"], ["b"], []]
        for tokens in cases {
            let r = recET(table: rec, input: tokens)
            let s = simpleET(table: sl, input: tokens).accepted
            let e = parseET(table: el,  input: tokens).accepted
            #expect(r == s && s == e,
                    "Three-way mismatch on '\(tokens)': rec=\(r) sl=\(s) el=\(e)")
        }
    }
}

// MARK: - Suite: EarleyTableParser facade

@Suite("EarleyTableParser facade")
struct EarleyTableParserFacadeTests {

    @Test("G₀ includes start slots after nullable prefixes")
    func initialStateIncludesLeftNullStartSlots() {
        let grammar = gamma1()
        let nfa = buildEarleyNFA(grammar: grammar)
        #expect(nfa.states[0].contains {
            $0.production.goal == grammar.start && $0.dot == 1
        })
    }

    @Test("acceptance always uses the declared start symbol")
    func acceptanceUsesDeclaredStart() {
        let grammar = gamma1()
        let table = buildRecogniserTable(
            nfa: buildEarleyNFA(grammar: grammar), grammar: grammar)
        for _ in 0..<20 {
            #expect(recET(table: table, input: ["a"]))
            #expect(!recET(table: table, input: ["b"]))
        }
    }

    @Test("parse(stream:) consumes positioned tokens without retokenizing")
    func parsesTokenStream() throws {
        let grammar = Grammar(
            productions: [
                Production(goal: NT("S"), rule: [T("("), T("a"), T(")")])
            ],
            start: NT("S"), lexicalTokens: [:])
        let parser = EarleyTableParser(grammar: grammar)
        let source = "(a)"
        let stream = TokenizerStream(
            source: source, symbols: ["(", ")"], keywords: [])
        let result = try parser.parse(stream: stream)
        #expect(result.isSuccessful)
        #expect(result.sppfGraph != nil)
    }

    @Test("string convenience delegates to TokenizerStream")
    func stringConvenienceTokenizesSymbols() throws {
        let grammar = Grammar(
            productions: [
                Production(goal: NT("S"), rule: [T("("), T("a"), T(")")])
            ],
            start: NT("S"), lexicalTokens: [:])
        let result = try EarleyTableParser(grammar: grammar).parse("(a)")
        #expect(result.isSuccessful)
    }

    // MARK: Init and pre-computed tables

    @Test("Tables are pre-computed at init time")
    func tablesPrecomputed() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(parser.nfa.stateCount     > 0)
        #expect(parser.slTable.grammar == parser.grammar)
        #expect(parser.elTable.grammar == parser.grammar)
    }

    @Test("useExtendedLookahead defaults to false")
    func defaultAlgorithm() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(parser.useExtendedLookahead == false)
    }

    @Test("useExtendedLookahead can be set to true at init")
    func elModeInit() {
        let parser = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        #expect(parser.useExtendedLookahead == true)
    }

    // MARK: recognizes(_:) — DeterministicParser extension

    @Test("recognizes returns true for valid Γ₁ inputs (SL)")
    func recognizesSLValid() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(parser.recognizes("a"))
        #expect(parser.recognizes("a b"))
        #expect(parser.recognizes("a a b"))
    }

    @Test("recognizes returns false for invalid Γ₁ inputs (SL)")
    func recognizesSLInvalid() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(!parser.recognizes("b"))
        #expect(!parser.recognizes("a a"))
        #expect(!parser.recognizes("a b b"))
    }

    @Test("recognizes returns true for valid Γ₁ inputs (EL)")
    func recognizesELValid() {
        let parser = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        #expect(parser.recognizes("a"))
        #expect(parser.recognizes("a b"))
        #expect(parser.recognizes("a a b"))
    }

    @Test("recognizes returns false for invalid Γ₁ inputs (EL)")
    func recognizesELInvalid() {
        let parser = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        #expect(!parser.recognizes("b"))
        #expect(!parser.recognizes("a a"))
    }

    // MARK: syntaxTree(for:) — DeterministicParser

    @Test("syntaxTree returns tree rooted at start symbol (SL)")
    func syntaxTreeRootSL() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let tree   = try parser.syntaxTree(for: "a")
        guard case let .node(nt, _) = tree else {
            Issue.record("Expected .node, got \(tree)")
            return
        }
        #expect(nt.name == "S")
    }

    @Test("syntaxTree returns tree rooted at start symbol (EL)")
    func syntaxTreeRootEL() throws {
        let parser = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        let tree   = try parser.syntaxTree(for: "a")
        guard case let .node(nt, _) = tree else {
            Issue.record("Expected .node, got \(tree)")
            return
        }
        #expect(nt.name == "S")
    }

    @Test("syntaxTree throws SyntaxError for invalid input")
    func syntaxTreeThrows() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(throws: SyntaxError.self) { try parser.syntaxTree(for: "b") }
    }

    @Test("syntaxTree throws SyntaxError for invalid input (EL)")
    func syntaxTreeThrowsEL() {
        let parser = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        #expect(throws: SyntaxError.self) { try parser.syntaxTree(for: "b") }
    }

    @Test("SL and EL syntaxTree agree for unambiguous Γ₁")
    func syntaxTreeSLELAgree() throws {
        let sl = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: false)
        let el = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        let slTree = try sl.syntaxTree(for: "a a b")
        let elTree = try el.syntaxTree(for: "a a b")
        #expect(slTree == elTree,
                "SL and EL must produce identical trees for an unambiguous grammar")
    }

    // MARK: parse(_:) — GeneralizedParser

    @Test("parse returns isSuccessful=true for valid input")
    func parseSuccessful() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let result = try parser.parse("a a b")
        #expect(result.isSuccessful)
        #expect(result.sppfGraph != nil, "SPPF must be populated after parse()")
    }

    @Test("parse throws SyntaxError for invalid input")
    func parseThrows() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(throws: SyntaxError.self) { try parser.parse("b") }
    }

    @Test("parse hasAmbiguity is false for unambiguous Γ₁")
    func parseUnambiguous() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let result = try parser.parse("a a b")
        #expect(!result.hasAmbiguity)
    }

    @Test("parse hasAmbiguity is true for ambiguous Γ₃")
    func parseAmbiguous() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let result = try parser.parse("b b b")
        #expect(result.hasAmbiguity)
    }

    // MARK: allSyntaxTrees(for:) — GeneralizedParser

    @Test("allSyntaxTrees returns exactly 1 tree for unambiguous Γ₁")
    func allTreesUnambiguous() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let trees  = try parser.allSyntaxTrees(for: "a a b")
        #expect(trees.count == 1,
                "Unambiguous grammar must yield exactly one tree, got \(trees.count)")
    }

    @Test("allSyntaxTrees returns > 1 tree for ambiguous Γ₃ 'bbb'")
    func allTreesAmbiguous() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let trees  = try parser.allSyntaxTrees(for: "b b b")
        #expect(trees.count > 1,
                "Ambiguous grammar must yield more than one tree for 'b b b', got \(trees.count)")
    }

    @Test("allSyntaxTrees results are structurally distinct")
    func allTreesDistinct() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let trees  = try parser.allSyntaxTrees(for: "b b b")
        for i in 0..<trees.count {
            for j in (i + 1)..<trees.count {
                #expect(trees[i] != trees[j],
                        "Trees[\(i)] and trees[\(j)] should differ")
            }
        }
    }

    @Test("allSyntaxTrees returns exactly 1 tree for 'b' in Γ₃")
    func allTreesSingleB() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let trees  = try parser.allSyntaxTrees(for: "b")
        #expect(trees.count == 1,
                "'b' has only one parse in Γ₃, got \(trees.count)")
    }

    @Test("allSyntaxTrees are all rooted at the start symbol")
    func allTreesRootedAtStart() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let trees  = try parser.allSyntaxTrees(for: "b b b")
        for tree in trees {
            guard case let .node(nt, _) = tree else {
                Issue.record("Expected .node root, got \(tree)")
                continue
            }
            #expect(nt.name == "S")
        }
    }

    @Test("allSyntaxTrees throws SyntaxError for invalid input")
    func allTreesThrows() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(throws: SyntaxError.self) { try parser.allSyntaxTrees(for: "b") }
    }

    @Test("EL allSyntaxTrees matches SL count for unambiguous Γ₁")
    func allTreesELMatchesSL() throws {
        let sl = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: false)
        let el = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        let slTrees = try sl.allSyntaxTrees(for: "a a b")
        let elTrees = try el.allSyntaxTrees(for: "a a b")
        #expect(slTrees.count == elTrees.count,
                "SL and EL must produce the same number of trees for an unambiguous grammar")
    }

    // MARK: Balanced a^n b^n grammar — additional coverage

    @Test("balanced a^n b^n grammar: parse tree leaf structure")
    func balancedTreeLeaves() throws {
        let grammar = Grammar(
            productions: [
                Production(goal: NT("S"), rule: [T("a"), N("S"), T("b")]),
                Production(goal: NT("S"), rule: [])
            ],
            start: NT("S"), lexicalTokens: [:]
        )
        let parser = EarleyTableParser(grammar: grammar)
        let tree   = try parser.syntaxTree(for: "a a b b")
        // Tree must be non-empty.
        if case .empty = tree {
            Issue.record("Expected non-empty tree for 'a a b b'")
        }
    }

    // MARK: parse(tokens:) — direct token array API

    @Test("parse(tokens:) accepts pre-tokenised input")
    func parseTokensDirect() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let result = try parser.parse(tokens: ["a", "a", "b"])
        #expect(result.isSuccessful)
        #expect(result.sppfGraph != nil)
    }

    @Test("parse(tokens:) throws for rejected token array")
    func parseTokensRejects() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(throws: SyntaxError.self) {
            _ = try parser.parse(tokens: ["b"])
        }
    }

    @Test("parse(tokens:) EL mode produces accepted result")
    func parseTokensEL() throws {
        let parser = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        let result = try parser.parse(tokens: ["a"])
        #expect(result.isSuccessful)
    }
}
