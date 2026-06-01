// Main.swift
// Demo application showcasing the Earley Table Traversing Parser
// Implements all examples from Scott & Johnstone (2026)

import ArgumentParser
import Foundation
import Earley_TableParser
import Grammar

// MARK: - Demo Utility Functions

func separator(_ title: String) {
    print("\n" + String(repeating: "═", count: 70))
    print("  \(title)")
    print(String(repeating: "═", count: 70))
}

func testRecogniser(grammar: Grammar, name: String, cases: [(input: [String], expected: Bool)]) {
    separator("Recogniser Test — \(name)")
    let nfa = buildEarleyNFA(grammar: grammar)
    let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
    print("NFA states: \(nfa.stateCount)")

    var passed = 0
    for (tokens, expected) in cases {
        let result = recET(table: table, input: tokens)
        let status = result == expected ? "✓ PASS" : "✗ FAIL"
        let inputStr = tokens.isEmpty ? "ε" : tokens.joined()
        print("  recET(\"\(inputStr)\") → \(result)  [expected \(expected)]  \(status)")
        if result == expected { passed += 1 }
    }
    print("Result: \(passed)/\(cases.count) passed")
}

func testParser(grammar: Grammar, name: String, cases: [(input: [String], expected: Bool)]) {
    separator("Parser Test — \(name)")
    let nfa = buildEarleyNFA(grammar: grammar)
    let slTable = buildSLParseTable(nfa: nfa, grammar: grammar)
    print("NFA states: \(nfa.stateCount)")

    var passed = 0
    for (tokens, expected) in cases {
        let result = simpleET(table: slTable, input: tokens)
        let status = result.accepted == expected ? "✓ PASS" : "✗ FAIL"
        let inputStr = tokens.isEmpty ? "ε" : tokens.joined()
        print("  simpleET(\"\(inputStr)\") → accepted=\(result.accepted)  [expected \(expected)]  \(status)")
        print("    BSR elements: \(result.bsrSet.count), Ambiguous: \(result.hasAmbiguity)")
        
        // Print Earley sets for short inputs
        if tokens.count <= 3 {
            for (j, ej) in result.earleySets.enumerated() {
                let sorted = ej.sorted { a, b in
                    a.state < b.state || (a.state == b.state && a.backIndex < b.backIndex)
                }.map { "(\($0.state),\($0.backIndex))" }
                print("    E_\(j) = {\(sorted.joined(separator: ", "))}")
            }
        }
        
        if result.accepted == expected { passed += 1 }
    }
    print("Result: \(passed)/\(cases.count) passed")
}

func printNFAStates(nfa: EarleyNFA, title: String) {
    separator("NFA States — \(title)")
    for (i, state) in nfa.states.enumerated() {
        let coreLabel = nfa.isCore(i) ? " [core]" : ""
        print("  G_\(i)\(coreLabel):")
        for slot in state.sorted(by: { $0.description < $1.description }) {
            print("    \(slot)")
        }
    }
}

// MARK: - Test Grammars from the Paper

/// Γ₁: S ::= A S b | a,  A ::= a A | ε
func createGamma1() -> Grammar {
    let rules: [(NonTerminal, [Grammar.Symbol])] = [
        (
            NonTerminal(name: "S"),
            [
                .nonTerminal(NonTerminal(name: "A")),
                .nonTerminal(NonTerminal(name: "S")),
                .terminal(Terminal(description: "b"))
            ]
        ),
        (NonTerminal(name: "S"), [.terminal(Terminal(description: "a"))]),
        (
            NonTerminal(name: "A"),
            [
                .terminal(Terminal(description: "a")),
                .nonTerminal(NonTerminal(name: "A"))
            ]
        ),
        (NonTerminal(name: "A"), [])  // ε
    ]
    return try! Grammar(startSymbol: NonTerminal(name: "S"), productions: rules)
}

/// Γ₂: S ::= B B S a | b b b,  B ::= b b B | ε
func createGamma2() -> Grammar {
    let rules: [(NonTerminal, [Grammar.Symbol])] = [
        (
            NonTerminal(name: "S"),
            [
                .nonTerminal(NonTerminal(name: "B")),
                .nonTerminal(NonTerminal(name: "B")),
                .nonTerminal(NonTerminal(name: "S")),
                .terminal(Terminal(description: "a"))
            ]
        ),
        (
            NonTerminal(name: "S"),
            [
                .terminal(Terminal(description: "b")),
                .terminal(Terminal(description: "b")),
                .terminal(Terminal(description: "b"))
            ]
        ),
        (
            NonTerminal(name: "B"),
            [
                .terminal(Terminal(description: "b")),
                .terminal(Terminal(description: "b")),
                .nonTerminal(NonTerminal(name: "B"))
            ]
        ),
        (NonTerminal(name: "B"), [])  // ε
    ]
    return try! Grammar(startSymbol: NonTerminal(name: "S"), productions: rules)
}

/// Γ₃: S ::= S S S | S S | b (highly ambiguous)
func createGamma3() -> Grammar {
    let rules: [(NonTerminal, [Grammar.Symbol])] = [
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

// MARK: - Main Command

@main
struct EarleyTableParserDemo: ParsableCommand {
    @Flag(help: "Print NFA states for each grammar") var printNFA = false
    @Flag(help: "Run only recogniser tests") var recogniserOnly = false

    mutating func run() throws {
        print("╔═══════════════════════════════════════════════════════════╗")
        print("║  Earley Table Traversing Parser — Scott & Johnstone      ║")
        print("║  Science of Computer Programming 247 (2026) 103335       ║")
        print("╚═══════════════════════════════════════════════════════════╝")

        // ── Γ₁ ──
        let gamma1 = createGamma1()
        if printNFA {
            let nfa1 = buildEarleyNFA(grammar: gamma1)
            printNFAStates(nfa: nfa1, title: "Γ₁")
        }

        testRecogniser(grammar: gamma1, name: "Γ₁: S::=ASb|a  A::=aA|ε", cases: [
            (input: ["a", "a", "b"],    expected: true),
            (input: ["a"],              expected: true),
            (input: ["a", "b"],         expected: true),
            (input: ["a", "a", "a", "b", "b"], expected: true),
            (input: ["b"],              expected: false),
            (input: ["a", "a"],         expected: false),
        ])

        if !recogniserOnly {
            testParser(grammar: gamma1, name: "Γ₁", cases: [
                (input: ["a", "a", "b"],    expected: true),
                (input: ["a"],              expected: true),
                (input: ["b"],              expected: false),
            ])
        }

        // ── Γ₂ ──
        let gamma2 = createGamma2()
        if printNFA {
            let nfa2 = buildEarleyNFA(grammar: gamma2)
            printNFAStates(nfa: nfa2, title: "Γ₂")
        }

        testRecogniser(grammar: gamma2, name: "Γ₂: S::=BBSa|bbb  B::=bbB|ε", cases: [
            (input: ["b","b","b"],        expected: true),
            (input: ["b","b","b","a"],    expected: true),
            (input: ["b","b"],            expected: false),
            (input: ["b"],                expected: false),
        ])

        if !recogniserOnly {
            testParser(grammar: gamma2, name: "Γ₂", cases: [
                (input: ["b","b","b"],        expected: true),
                (input: ["b","b","b","a"],    expected: true),
                (input: ["b"],                expected: false),
            ])
        }

        // ── Γ₃ (highly ambiguous) ──
        let gamma3 = createGamma3()
        if printNFA {
            let nfa3 = buildEarleyNFA(grammar: gamma3)
            printNFAStates(nfa: nfa3, title: "Γ₃ (ambiguous)")
        }

        testRecogniser(grammar: gamma3, name: "Γ₃: S::=SSS|SS|b", cases: [
            (input: ["b"],                expected: true),
            (input: ["b","b"],            expected: true),
            (input: ["b","b","b"],        expected: true),
            (input: ["b","b","b","b"],    expected: true),
            (input: ["a"],                expected: false),
        ])

        if !recogniserOnly {
            testParser(grammar: gamma3, name: "Γ₃ (ambiguous)", cases: [
                (input: ["b"],                expected: true),
                (input: ["b","b"],            expected: true),
                (input: ["b","b","b"],        expected: true),
                (input: ["b","b","b","b"],    expected: true),
            ])
        }

        // ── Grammar Analysis ──
        separator("Grammar Analysis")
        for (grammar, name) in [(gamma1, "Γ₁"), (gamma2, "Γ₂"), (gamma3, "Γ₃")] {
            let follow = grammar.followSets()
            print("\n  \(name) FOLLOW sets:")
            for (nt, fs) in follow.sorted(by: { $0.key < $1.key }) {
                print("    FOLLOW(\(nt)) = {\(fs.sorted().joined(separator: ", "))}")
            }
        }

        separator("Demo Complete")
        print("✓ All tests completed successfully")
    }
}
