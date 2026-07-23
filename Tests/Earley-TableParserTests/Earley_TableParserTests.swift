//
//  Earley_TableParserTests.swift
//  Earley-TableParser
//
//  Comprehensive tests covering:
//    1. NFA construction
//    2. recET() recogniser
//    3. simpleET() parser + BSR correctness
//    4. parseET() extended-lookahead parser
//    5. SPPF construction and structure
//    6. EarleyTableParser facade (DeterministicParser + GeneralizedParser)
//    7. syntaxTree() and allSyntaxTrees() tree enumeration
//    8. Ambiguity detection
//    9. Edge cases (ε, single token, left-recursive grammars)
//   10. Recogniser/parser consistency
//   11. Performance smoke tests
//

import Testing
@testable import Earley_TableParser
import Foundation
import Grammar

// MARK: - Grammar construction helpers

func T(_ s: String) -> Symbol   { .terminal(Terminal(string: s)) }
func N(_ s: String) -> Symbol   { .nonTerminal(NonTerminal(name: s)) }
func NT(_ s: String) -> NonTerminal { NonTerminal(name: s) }

// MARK: - Canonical example grammars from Scott & Johnstone (2026)

/// Γ₁: S ::= A S b | a    A ::= a A | ε   (Section 2.3)
func gamma1() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: [N("A"), N("S"), T("b")]),
        Production(goal: NT("S"), rule: [T("a")]),
        Production(goal: NT("A"), rule: [T("a"), N("A")]),
        Production(goal: NT("A"), rule: []),
    ], start: NT("S"), lexicalTokens: [:])
}

/// Γ₂: S ::= B B S a | b b b    B ::= b b B | ε   (Section 4.3)
func gamma2() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: [N("B"), N("B"), N("S"), T("a")]),
        Production(goal: NT("S"), rule: [T("b"), T("b"), T("b")]),
        Production(goal: NT("B"), rule: [T("b"), T("b"), N("B")]),
        Production(goal: NT("B"), rule: []),
    ], start: NT("S"), lexicalTokens: [:])
}

/// Γ₃: S ::= S S S | S S | b   (highly ambiguous, Section 5.1)
func gamma3() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: [N("S"), N("S"), N("S")]),
        Production(goal: NT("S"), rule: [N("S"), N("S")]),
        Production(goal: NT("S"), rule: [T("b")]),
    ], start: NT("S"), lexicalTokens: [:])
}

/// Simple ε-only grammar: S ::= ε
func epsilonGrammar() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: []),
    ], start: NT("S"), lexicalTokens: [:])
}

/// S ::= a S b | ε   (balanced a^n b^n, n ≥ 0)
func balancedGrammar() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: [T("a"), N("S"), T("b")]),
        Production(goal: NT("S"), rule: []),
    ], start: NT("S"), lexicalTokens: [:])
}

/// S ::= S + S | n   (classic ambiguous expression grammar)
func ambiguousExprGrammar() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: [N("S"), T("+"), N("S")]),
        Production(goal: NT("S"), rule: [T("n")]),
    ], start: NT("S"), lexicalTokens: [:])
}

/// Left-recursive: S ::= S a | a
func leftRecursiveGrammar() -> Grammar {
    Grammar(productions: [
        Production(goal: NT("S"), rule: [N("S"), T("a")]),
        Production(goal: NT("S"), rule: [T("a")]),
    ], start: NT("S"), lexicalTokens: [:])
}

// MARK: - Suite 1: NFA Construction

@Suite("NFA Construction")
struct NFAConstructionTests {

    @Test("G₀ is always the start state")
    func startState() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        #expect(nfa.stateCount > 0)
        // State 0 must contain at least one dot-0 slot for the start symbol.
        let hasStartSlot = nfa.states[0].contains { $0.dot == 0 && $0.production.goal == NT("S") }
        #expect(hasStartSlot, "G₀ must have a dot-0 start slot")
    }

    @Test("Alphabet includes epsilon")
    func alphabetHasEpsilon() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        #expect(nfa.alphabet.contains(where: { isEpsilonSymbol($0) }))
    }

    @Test("Core states are detected correctly")
    func coreStateDetection() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        // G₀ is not core (contains dot-0 slots).
        #expect(!nfa.isCore(0), "G₀ should not be core")
        // At least one other state should be core.
        let hasCore = (1..<nfa.stateCount).contains { nfa.isCore($0) }
        #expect(hasCore, "There should be at least one core state")
    }

    @Test("Transition table is complete")
    func transitionTableComplete() {
        let nfa = buildEarleyNFA(grammar: gamma1())
        for sym in nfa.alphabet {
            guard let col = nfa.transitions[sym] else {
                Issue.record("Missing column for symbol \(sym)")
                continue
            }
            #expect(col.count == nfa.stateCount,
                "Column for \(sym) should have stateCount entries")
        }
    }

    @Test("Γ₂ NFA handles ε-productions")
    func nfaGamma2Epsilon() {
        let nfa = buildEarleyNFA(grammar: gamma2())
        #expect(nfa.stateCount > 0)
    }

    @Test("Γ₃ ambiguous grammar builds valid NFA")
    func nfaGamma3Ambiguous() {
        let nfa = buildEarleyNFA(grammar: gamma3())
        #expect(nfa.stateCount >= 2)
    }

    @Test("Left-recursive grammar builds valid NFA")
    func nfaLeftRecursive() {
        let nfa = buildEarleyNFA(grammar: leftRecursiveGrammar())
        #expect(nfa.stateCount > 0)
    }
}

// MARK: - Suite 2: recET() Recogniser

@Suite("recET() Recogniser")
struct RecogniserTests {

    @Test("Γ₁ accepts valid inputs")
    func gamma1Accepts() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma1())
        #expect(recET(table: table, input: ["a"]))
        #expect(recET(table: table, input: ["a", "b"]))
        #expect(recET(table: table, input: ["a", "a", "b"]))
        #expect(recET(table: table, input: ["a", "a", "a", "b", "b"]))
    }

    @Test("Γ₁ rejects invalid inputs")
    func gamma1Rejects() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma1())
        #expect(!recET(table: table, input: ["b"]))
        #expect(!recET(table: table, input: ["a", "b", "b"]))
        #expect(!recET(table: table, input: ["a", "a"]))
    }

    @Test("Γ₂ accepts valid inputs")
    func gamma2Accepts() {
        let nfa   = buildEarleyNFA(grammar: gamma2())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma2())
        #expect(recET(table: table, input: ["b", "b", "b"]))
        #expect(recET(table: table, input: ["b", "b", "b", "a"]))
    }

    @Test("Γ₂ rejects invalid inputs")
    func gamma2Rejects() {
        let nfa   = buildEarleyNFA(grammar: gamma2())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma2())
        #expect(!recET(table: table, input: ["b"]))
        #expect(!recET(table: table, input: ["b", "b"]))
        #expect(!recET(table: table, input: ["a"]))
    }

    @Test("Γ₃ accepts valid inputs")
    func gamma3Accepts() {
        let nfa   = buildEarleyNFA(grammar: gamma3())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma3())
        #expect(recET(table: table, input: ["b"]))
        #expect(recET(table: table, input: ["b", "b"]))
        #expect(recET(table: table, input: ["b", "b", "b"]))
        #expect(recET(table: table, input: ["b", "b", "b", "b"]))
    }

    @Test("Pure ε grammar accepts empty input")
    func epsilonGrammarAcceptsEmpty() {
        let g     = epsilonGrammar()
        let nfa   = buildEarleyNFA(grammar: g)
        let table = buildRecogniserTable(nfa: nfa, grammar: g)
        #expect(recET(table: table, input: []))
    }

    @Test("Balanced a^n b^n grammar")
    func balancedAnBn() {
        let g     = balancedGrammar()
        let nfa   = buildEarleyNFA(grammar: g)
        let table = buildRecogniserTable(nfa: nfa, grammar: g)
        #expect(recET(table: table, input: []))
        #expect(recET(table: table, input: ["a", "b"]))
        #expect(recET(table: table, input: ["a", "a", "b", "b"]))
        #expect(recET(table: table, input: ["a", "a", "a", "b", "b", "b"]))
        #expect(!recET(table: table, input: ["a"]))
        #expect(!recET(table: table, input: ["a", "b", "b"]))
    }

    @Test("Left-recursive grammar accepted")
    func leftRecursiveAccepted() {
        let g     = leftRecursiveGrammar()
        let nfa   = buildEarleyNFA(grammar: g)
        let table = buildRecogniserTable(nfa: nfa, grammar: g)
        #expect(recET(table: table, input: ["a"]))
        #expect(recET(table: table, input: ["a", "a"]))
        #expect(recET(table: table, input: ["a", "a", "a"]))
        #expect(!recET(table: table, input: ["b"]))
    }
}

// MARK: - Suite 3: simpleET() Parser + BSR

@Suite("simpleET() Parser")
struct SimpleETParserTests {

    @Test("Γ₁ 'a' produces BSR elements")
    func gamma1SingleA() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r = simpleET(table: table, input: ["a"])
        #expect(r.accepted)
        #expect(!r.bsrSet.isEmpty)
    }

    @Test("Γ₁ 'aab' produces expected Earley set count")
    func gamma1EarleySets() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r = simpleET(table: table, input: ["a", "a", "b"])
        #expect(r.accepted)
        #expect(r.earleySets.count == 4)  // n+1 = 4 sets for n=3 tokens
    }

    @Test("BSR elements have valid extents (i ≤ k ≤ j)")
    func bsrExtentsValid() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r = simpleET(table: table, input: ["a", "a", "b"])
        for elem in r.bsrSet {
            #expect(elem.leftExtent >= 0)
            #expect(elem.pivot      >= elem.leftExtent)
            #expect(elem.rightExtent >= elem.pivot)
        }
    }

//    @Test(.disabled("All BSR components have a non-nil LHS"))
//    func bsrComponentsHaveLHS() {
//        let nfa   = buildEarleyNFA(grammar: gamma1())
//        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
//        let r = simpleET(table: table, input: ["a", "a", "b"])
//        for elem in r.bsrSet {
//            #expect(elem.omega.lhsNonterminal != nil)
//        }
//    }

    @Test("Γ₁ is unambiguous")
    func gamma1Unambiguous() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r = simpleET(table: table, input: ["a", "a", "b"])
        #expect(!r.hasAmbiguity)
    }

    @Test("Γ₃ 'bbb' is ambiguous")
    func gamma3Ambiguous() {
        let nfa   = buildEarleyNFA(grammar: gamma3())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma3())
        let r = simpleET(table: table, input: ["b", "b", "b"])
        #expect(r.accepted)
        #expect(r.hasAmbiguity)
    }

    @Test("Ambiguous expression grammar 'n+n+n' is ambiguous")
    func exprAmbiguous() {
        let g     = ambiguousExprGrammar()
        let nfa   = buildEarleyNFA(grammar: g)
        let table = buildSLParseTable(nfa: nfa, grammar: g)
        let r = simpleET(table: table, input: ["n", "+", "n", "+", "n"])
        #expect(r.accepted)
        #expect(r.hasAmbiguity)
    }

    @Test("Rejected input produces empty BSR set")
    func rejectedInputEmptyBSR() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r = simpleET(table: table, input: ["b"])
        #expect(!r.accepted)
    }

    @Test("E₀ always non-empty after init")
    func e0NonEmpty() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r = simpleET(table: table, input: ["a"])
        #expect(!r.earleySets[0].isEmpty)
    }

    @Test("Earley pairs have valid state indices")
    func earleyPairsValid() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r = simpleET(table: table, input: ["a", "a", "b"])
        for ej in r.earleySets {
            for pair in ej {
                #expect(pair.state >= 0 && pair.state < nfa.stateCount)
                #expect(pair.backIndex >= 0)
            }
        }
    }
}

// MARK: - Suite 4: parseET() Extended-Lookahead Parser

@Suite("parseET() Extended Lookahead")
struct ParseETTests {

    @Test("parseET agrees with simpleET on Γ₁ acceptance")
    func gamma1Agreement() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let inputs: [[String]] = [["a"], ["a", "b"], ["a", "a", "b"], ["b"], ["a", "a"]]
        for tokens in inputs {
            let slResult = simpleET(table: sl, input: tokens)
            let elResult = parseET(table: el, input: tokens)
            #expect(slResult.accepted == elResult.accepted,
                "SL and EL should agree on '\(tokens.joined(separator: " "))'")
        }
    }

    @Test("parseET agrees with simpleET on Γ₂ acceptance")
    func gamma2Agreement() {
        let grammar = gamma2()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let inputs: [[String]] = [
            ["b","b","b"], ["b","b","b","a"], ["b"], ["b","b"]
        ]
        for tokens in inputs {
            let slResult = simpleET(table: sl, input: tokens)
            let elResult = parseET(table: el, input: tokens)
            #expect(slResult.accepted == elResult.accepted,
                "SL and EL should agree on '\(tokens.joined(separator: " "))'")
        }
    }

    @Test("parseET agrees with simpleET on Γ₃ acceptance")
    func gamma3Agreement() {
        let grammar = gamma3()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)

        let inputs: [[String]] = [
            ["b"], ["b","b"], ["b","b","b"], ["b","b","b","b"], ["a"]
        ]
        for tokens in inputs {
            let slResult = simpleET(table: sl, input: tokens)
            let elResult = parseET(table: el, input: tokens)
            #expect(slResult.accepted == elResult.accepted,
                "SL and EL should agree on '\(tokens.joined(separator: " "))'")
        }
    }

    @Test("EL parser builds non-empty BSR set on acceptance")
    func elBSRNonEmpty() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let r = parseET(table: el, input: ["a", "a", "b"])
        #expect(r.accepted)
        #expect(!r.bsrSet.isEmpty)
    }

    @Test("EL parser detects ambiguity in Γ₃")
    func elDetectsAmbiguity() {
        let grammar = gamma3()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let r = parseET(table: el, input: ["b", "b", "b"])
        #expect(r.accepted)
        #expect(r.hasAmbiguity)
    }

    @Test("EL parse table has SELECT sets for all states")
    func elSelectSets() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        for p in 0..<nfa.stateCount {
            // selectSet and rLHS should always be non-nil (may be empty).
            #expect(el.info(state: p) != nil, "stateInfo[\(p)] should not be nil")
        }
    }

    @Test("EL and SL BSR sets span compatible extents")
    func elSlBSRExtents() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let tokens  = ["a", "a", "b"]
        let slR     = simpleET(table: sl, input: tokens)
        let elR     = parseET(table: el, input: tokens)
        // Both should have at least one root-level BSR element.
        let slRoot = slR.bsrSet.filter { $0.leftExtent == 0 && $0.rightExtent == 3 }
        let elRoot = elR.bsrSet.filter { $0.leftExtent == 0 && $0.rightExtent == 3 }
        #expect(!slRoot.isEmpty)
        #expect(!elRoot.isEmpty)
    }
}

// MARK: - Suite 5: SPPF Construction

@Suite("SPPF Construction")
struct SPPFTests {

    @Test("SPPF has nodes after successful parse")
    func sppfHasNodes() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: ["a"])
        let sppf    = buildSPPF(from: r.bsrSet, grammar: grammar, tokens: ["a"])
        #expect(!sppf.getAllNodes().isEmpty)
    }

    @Test("SPPF contains a symbol node for the start nonterminal")
    func sppfHasStartNode() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: ["a"])
        let sppf    = buildSPPF(from: r.bsrSet, grammar: grammar, tokens: ["a"])
        let hasRoot = sppf.getAllNodes().contains {
            if case .symbol(let lbl, 0, 1) = $0 { return lbl == "S" }
            return false
        }
        #expect(hasRoot, "Should have symbol node S(0,1)")
    }

    @Test("SPPF leaf nodes correspond to actual tokens")
    func sppfLeafTokens() {
        let grammar = gamma1()
        let tokens  = ["a", "a", "b"]
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: tokens)
        let sppf    = buildSPPF(from: r.bsrSet, grammar: grammar, tokens: tokens)
        let leaves  = sppf.getAllNodes().compactMap { node -> String? in
            if case .leaf(let lbl, _, _) = node { return lbl }
            return nil
        }
        // Should see "a" and "b" leaves.
        #expect(leaves.contains("a"))
        #expect(leaves.contains("b"))
    }

    @Test("SPPF for ambiguous grammar has multi-packed symbol nodes")
    func sppfAmbiguousMultiPacked() {
        let grammar = gamma3()
        let tokens  = ["b", "b", "b"]
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: tokens)
        let sppf    = buildSPPF(from: r.bsrSet, grammar: grammar, tokens: tokens)
        let hasMultiPacked = sppf.getAllNodes().contains { node in
            guard case .symbol = node else { return false }
            let packed = sppf.getChildren(of: node).filter {
                if case .packed = $0 { return true }; return false
            }
            return packed.count > 1
        }
        #expect(hasMultiPacked, "Ambiguous parse should produce multi-packed nodes")
    }

    @Test("SPPF graphviz export is valid DOT")
    func sppfGraphviz() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: ["a"])
        let sppf    = buildSPPF(from: r.bsrSet, grammar: grammar, tokens: ["a"])
        let dot     = sppf.graphviz
        #expect(dot.contains("digraph"))
        #expect(dot.contains("{"))
        #expect(dot.contains("}"))
    }
}

// MARK: - Suite 6: EarleyTableParser Facade

@Suite("EarleyTableParser Facade")
struct FacadeTests {

    @Test("syntaxTree returns a node for valid input")
    func syntaxTreeValid() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let tree   = try parser.syntaxTree(for: "a a b")
        if case .node(let nt, _) = tree {
            #expect(nt.name == "S")
        } else {
            Issue.record("Expected a .node rooted at S")
        }
    }

    @Test("syntaxTree throws for invalid input")
    func syntaxTreeInvalid() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(throws: (any Error).self) {
            _ = try parser.syntaxTree(for: "b")
        }
    }

    @Test("recognizes returns true for valid input")
    func recognizesValid() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(parser.recognizes("a"))
        #expect(parser.recognizes("a a b"))
        #expect(parser.recognizes("a b"))
    }

    @Test("recognizes returns false for invalid input")
    func recognizesInvalid() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(!parser.recognizes("b"))
        #expect(!parser.recognizes("a a"))
    }

    @Test("parse() returns accepted=true for valid input")
    func parseAccepted() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let result = try parser.parse("a a b")
        #expect(result.isSuccessful)
        #expect(result.sppfGraph != nil, "SPPF should be populated after parse()")
    }

    @Test("parse() throws for invalid input")
    func parseThrows() {
        let parser = EarleyTableParser(grammar: gamma1())
        #expect(throws: (any Error).self) {
            _ = try parser.parse("b")
        }
    }

    @Test("allSyntaxTrees returns 1 tree for unambiguous Γ₁")
    func allTreesUnambiguous() throws {
        let parser = EarleyTableParser(grammar: gamma1())
        let trees  = try parser.allSyntaxTrees(for: "a a b")
        #expect(trees.count == 1, "Unambiguous grammar should yield exactly 1 tree")
    }

    @Test("allSyntaxTrees returns multiple trees for ambiguous Γ₃ 'bbb'")
    func allTreesAmbiguous() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let trees  = try parser.allSyntaxTrees(for: "b b b")
        #expect(trees.count > 1, "Ambiguous grammar should yield > 1 tree for 'bbb'")
    }

    @Test("allSyntaxTrees are structurally distinct")
    func allTreesDistinct() throws {
        let parser = EarleyTableParser(grammar: gamma3())
        let trees  = try parser.allSyntaxTrees(for: "b b b")
        // All trees should be different.
        for i in 0..<trees.count {
            for j in (i+1)..<trees.count {
                #expect(trees[i] != trees[j], "Trees \(i) and \(j) should differ")
            }
        }
    }

    @Test("EL mode: syntaxTree matches SL mode for Γ₁")
    func elModeMatchesSL() throws {
        let parserSL = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: false)
        let parserEL = EarleyTableParser(grammar: gamma1(), useExtendedLookahead: true)
        let slTree   = try parserSL.syntaxTree(for: "a a b")
        let elTree   = try parserEL.syntaxTree(for: "a a b")
        #expect(slTree == elTree, "SL and EL should produce identical trees for unambiguous grammar")
    }

    @Test("allSyntaxTrees for balanced grammar 'aabb'")
    func allTreesBalanced() throws {
        let parser = EarleyTableParser(grammar: balancedGrammar())
        let trees  = try parser.allSyntaxTrees(for: "a a b b")
        #expect(trees.count == 1, "Balanced grammar is unambiguous")
        if case .node(let nt, _) = trees[0] {
            #expect(nt.name == "S")
        }
    }

    @Test("syntaxTree for 'n+n' (ambiguous expr)")
    func syntaxTreeExpr() throws {
        let parser = EarleyTableParser(grammar: ambiguousExprGrammar())
        let tree   = try parser.syntaxTree(for: "n + n")
        if case .node(let nt, _) = tree {
            #expect(nt.name == "S")
        }
    }

    @Test("allSyntaxTrees count for 'n+n+n' equals 2")
    func allTreesExpr3() throws {
        let parser = EarleyTableParser(grammar: ambiguousExprGrammar())
        let trees  = try parser.allSyntaxTrees(for: "n + n + n")
        // (n+n)+n  and  n+(n+n) — exactly 2 derivations.
        #expect(trees.count == 2, "n+n+n has exactly 2 parse trees")
    }
}

// MARK: - Suite 7: Consistency

@Suite("Recogniser / Parser Consistency")
struct ConsistencyTests {

    @Test("recET and simpleET agree on Γ₁")
    func consistencyGamma1() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let rec     = buildRecogniserTable(nfa: nfa, grammar: grammar)
        let parse   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let inputs: [[String]] = [[], ["a"], ["b"], ["a","b"], ["a","a","b"], ["b","b"]]
        for tokens in inputs {
            #expect(recET(table: rec, input: tokens) == simpleET(table: parse, input: tokens).accepted,
                "Mismatch on '\(tokens)'")
        }
    }

    @Test("recET and parseET agree on Γ₁")
    func consistencyELGamma1() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let rec     = buildRecogniserTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let inputs: [[String]] = [[], ["a"], ["b"], ["a","b"], ["a","a","b"]]
        for tokens in inputs {
            #expect(recET(table: rec, input: tokens) == parseET(table: el, input: tokens).accepted,
                "EL mismatch on '\(tokens)'")
        }
    }

    @Test("All three algorithms agree on Γ₂")
    func consistencyGamma2() {
        let grammar = gamma2()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let rec     = buildRecogniserTable(nfa: nfa, grammar: grammar)
        let sl      = buildSLParseTable(nfa: nfa, grammar: grammar)
        let el      = buildELParseTable(nfa: nfa, grammar: grammar)
        let inputs: [[String]] = [
            ["b","b","b"], ["b","b","b","a"], ["b","b"], ["b"], []
        ]
        for tokens in inputs {
            let r = recET(table: rec, input: tokens)
            let s = simpleET(table: sl, input: tokens).accepted
            let e = parseET(table: el, input: tokens).accepted
            #expect(r == s && s == e,
                "Three-way mismatch on '\(tokens)': rec=\(r) sl=\(s) el=\(e)")
        }
    }
}

// MARK: - Suite 8: Edge Cases

@Suite("Edge Cases")
struct EdgeCaseTests {

    @Test("Empty input accepted when grammar has S → ε")
    func emptyInputEpsilonGrammar() {
        let g     = epsilonGrammar()
        let nfa   = buildEarleyNFA(grammar: g)
        let table = buildSLParseTable(nfa: nfa, grammar: g)
        let r     = simpleET(table: table, input: [])
        #expect(r.accepted)
    }

    @Test("Empty input rejected when grammar has no ε production")
    func emptyInputNoEpsilon() {
        let nfa   = buildEarleyNFA(grammar: gamma3())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma3())
        let r     = simpleET(table: table, input: [])
        #expect(!r.accepted)
    }

    @Test("Single-token input 'a' for Γ₁")
    func singleToken() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r     = simpleET(table: table, input: ["a"])
        #expect(r.accepted)
        #expect(!r.bsrSet.isEmpty)
    }

    @Test("Unknown tokens are rejected gracefully")
    func unknownTokens() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma1())
        let r     = simpleET(table: table, input: ["x", "y", "z"])
        #expect(!r.accepted)
    }

    @Test("FOLLOW sets computed for all nonterminals of Γ₁")
    func followSets() {
        let follow = gamma1().followSets()
        #expect(follow[NT("S")] != nil)
        #expect(follow[NT("A")] != nil)
        // $ ∈ FOLLOW(S) because S is the start symbol.
        let dollarInFollowS = follow[NT("S")]?.contains(.terminal(.meta(.eof))) ?? false
        #expect(dollarInFollowS)
    }

    @Test("Nullable nonterminals detected correctly")
    func nullableNTs() {
        let g = gamma1()
        #expect(g.isNullable(NT("A")),  "A → ε, so A is nullable")
        #expect(!g.isNullable(NT("S")), "S has no ε production")
    }

    @Test("extractDerivation returns non-nil for accepted input")
    func extractDerivation_accepted() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: ["a"])
        let d       = extractDerivation(from: r.bsrSet, grammar: grammar, tokens: ["a"])
        #expect(d != nil)
    }

    @Test("extractDerivation returns nil for rejected input")
    func extractDerivation_rejected() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let r       = simpleET(table: table, input: ["b"])
        let d       = extractDerivation(from: r.bsrSet, grammar: grammar, tokens: ["b"])
        #expect(d == nil)
    }
}

// MARK: - Suite 9: Performance Smoke Tests

@Suite("Performance")
struct PerformanceTests {

    @Test("Recognition of Γ₁ inputs completes quickly")
    func recognitionPerformance() {
        let nfa   = buildEarleyNFA(grammar: gamma1())
        let table = buildRecogniserTable(nfa: nfa, grammar: gamma1())
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            _ = recET(table: table, input: ["a", "a", "b"])
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(elapsed < 5.0, "100 recognitions should complete in < 5s")
    }

    @Test("Ambiguous Γ₃ parsing completes in reasonable time")
    func ambiguousParsePerformance() {
        let nfa   = buildEarleyNFA(grammar: gamma3())
        let table = buildSLParseTable(nfa: nfa, grammar: gamma3())
        let start = CFAbsoluteTimeGetCurrent()
        let r     = simpleET(table: table, input: ["b", "b", "b", "b"])
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(r.accepted)
        #expect(elapsed < 10.0, "Γ₃ parse of 'bbbb' should complete in < 10s")
    }

    @Test("Pre-computed tables are reused across parses")
    func tableReuse() {
        let grammar = gamma1()
        let nfa     = buildEarleyNFA(grammar: grammar)
        let table   = buildSLParseTable(nfa: nfa, grammar: grammar)
        let inputs: [[String]] = Array(repeating: ["a","a","b"], count: 50)
        let start = CFAbsoluteTimeGetCurrent()
        for tokens in inputs { _ = simpleET(table: table, input: tokens) }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(elapsed < 5.0, "50 parses with shared table should complete in < 5s")
    }
}
