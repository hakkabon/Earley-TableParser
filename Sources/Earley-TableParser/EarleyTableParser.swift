// The Swift Programming Language
// https://docs.swift.org/swift-book
// 
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation
//
// Test driver that reproduces all examples from Scott & Johnstone (2025).
//
// Example grammars used in the paper:
//   Γ₁: S ::= A S b | a,  A ::= a A | ε
//   Γ₂: S ::= B B S a | b b b,  B ::= b b B | ε
//   Γ₃: S ::= S S S | S S | b   (highly ambiguous)

import ArgumentParser
import Foundation

// MARK: - Convenience grammar builder helpers

func T(_ s: String) -> Symbol { .terminal(s) }
func N(_ s: String) -> Symbol { .nonterminal(s) }
let eps: Symbol = .epsilon

// MARK: - Grammar Γ₁  (Section 2.3, Figure example throughout paper)

let gamma1 = Grammar(
    startSymbol: "S",
    rules: [
        (lhs: "S", rhs: [N("A"), N("S"), T("b")]),
        (lhs: "S", rhs: [T("a")]),
        (lhs: "A", rhs: [T("a"), N("A")]),
        (lhs: "A", rhs: []),        // ε-production
    ]
)

// MARK: - Grammar Γ₂  (Section 4.3 / 5.1 / 6.3)

let gamma2 = Grammar(
    startSymbol: "S",
    rules: [
        (lhs: "S", rhs: [N("B"), N("B"), N("S"), T("a")]),
        (lhs: "S", rhs: [T("b"), T("b"), T("b")]),
        (lhs: "B", rhs: [T("b"), T("b"), N("B")]),
        (lhs: "B", rhs: []),        // ε-production
    ]
)

// MARK: - Grammar Γ₃  (Section 5.1, highly ambiguous)

let gamma3 = Grammar(
    startSymbol: "S",
    rules: [
        (lhs: "S", rhs: [N("S"), N("S"), N("S")]),
        (lhs: "S", rhs: [N("S"), N("S")]),
        (lhs: "S", rhs: [T("b")]),
    ]
)

// MARK: - Test harness

func separator(_ title: String) {
    print("\n" + String(repeating: "═", count: 60))
    print("  \(title)")
    print(String(repeating: "═", count: 60))
}

func testRecogniser(grammar: Grammar, name: String, cases: [(input: [String], expected: Bool)]) {
    separator("Recogniser test — \(name)")
    let nfa   = buildEarleyNFA(grammar: grammar)
    let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
    print("NFA states: \(nfa.stateCount)")

    for (tokens, expected) in cases {
        let result = recET(table: table, input: tokens)
        let status = result == expected ? "✓" : "✗ FAIL"
        let inputStr = tokens.isEmpty ? "ε" : tokens.joined()
        print("  recET(\"\(inputStr)\") → \(result)  [expected \(expected)]  \(status)")
    }
}

func testParser(grammar: Grammar, name: String, cases: [(input: [String], expected: Bool)]) {
    separator("Parser test — \(name)")
    let nfa      = buildEarleyNFA(grammar: grammar)
    let slTable  = buildSLParseTable(nfa: nfa, grammar: grammar)
    print("NFA states: \(nfa.stateCount)")

    for (tokens, expected) in cases {
        let result   = simpleET(table: slTable, input: tokens)
        let status   = result.accepted == expected ? "✓" : "✗ FAIL"
        let inputStr = tokens.isEmpty ? "ε" : tokens.joined()
        print("  simpleET(\"\(inputStr)\") → accepted=\(result.accepted)  [expected \(expected)]  \(status)")
        print("    BSR elements: \(result.bsrSet.count)")

        // Print Earley sets for short inputs.
        if tokens.count <= 4 {
            for (j, ej) in result.earleySets.enumerated() {
                let sorted = ej.sorted { a, b in
                    a.state < b.state || (a.state == b.state && a.backIndex < b.backIndex)
                }.map { "(\($0.state),\($0.backIndex))" }
                print("    𝔼_\(j) = {\(sorted.joined(separator: ", "))}")
            }
        }
    }
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



@main
struct EarleyTableParser: ParsableCommand {
    mutating func run() throws {


        // MARK: - Run all tests

        print("╔══════════════════════════════════════════════════════════╗")
        print("║   Earley Table Traversing Parser — Scott & Johnstone     ║")
        print("║   Science of Computer Programming 247 (2026) 103335      ║")
        print("╚══════════════════════════════════════════════════════════╝")

        // ── Γ₁ NFA structure ──
        let nfa1 = buildEarleyNFA(grammar: gamma1)
        printNFAStates(nfa: nfa1, title: "Γ₁")

        // ── Γ₁ Recogniser ──
        testRecogniser(grammar: gamma1, name: "Γ₁: S::=ASb|a  A::=aA|ε", cases: [
            (input: ["a", "a", "b"],    expected: true),   // paper example in §2.3
            (input: ["a"],              expected: true),
            (input: ["a", "b"],         expected: true),   // A→ε, S→a, S→ASb
            (input: ["a", "a", "a", "b", "b"], expected: true),
            (input: ["b"],              expected: false),
            (input: ["a", "a"],         expected: false),
        ])

        // ── Γ₁ Parser ──
        testParser(grammar: gamma1, name: "Γ₁", cases: [
            (input: ["a", "a", "b"],    expected: true),
            (input: ["a"],              expected: true),
            (input: ["b"],              expected: false),
        ])

        // ── Γ₂ NFA structure ──
        let nfa2 = buildEarleyNFA(grammar: gamma2)
        printNFAStates(nfa: nfa2, title: "Γ₂")

        // ── Γ₂ Recogniser ──
        testRecogniser(grammar: gamma2, name: "Γ₂: S::=BBSa|bbb  B::=bbB|ε", cases: [
            (input: ["b","b","b"],        expected: true),
            (input: ["b","b","b","b"],    expected: true),  // §5.2 example: bbba
            (input: ["b","b","b","a"],    expected: true),  // bbba with B→ε,ε
            (input: ["b"],                expected: false),
            (input: ["b","b"],            expected: false),
        ])

        // ── Γ₂ Parser ──
        testParser(grammar: gamma2, name: "Γ₂", cases: [
            (input: ["b","b","b"],        expected: true),
            (input: ["b","b","b","a"],    expected: true),
            (input: ["b"],                expected: false),
        ])

        // ── Γ₃ NFA structure ──
        let nfa3 = buildEarleyNFA(grammar: gamma3)
        printNFAStates(nfa: nfa3, title: "Γ₃")

        // ── Γ₃ Recogniser (highly ambiguous) ──
        testRecogniser(grammar: gamma3, name: "Γ₃: S::=SSS|SS|b", cases: [
            (input: ["b"],                expected: true),
            (input: ["b","b"],            expected: true),
            (input: ["b","b","b"],        expected: true),   // §5.1 example
            (input: ["b","b","b","b"],    expected: true),
            (input: ["a"],                expected: false),
        ])

        // ── Γ₃ Parser (verify BSR counts reflect ambiguity) ──
        testParser(grammar: gamma3, name: "Γ₃", cases: [
            (input: ["b"],                expected: true),
            (input: ["b","b"],            expected: true),
            (input: ["b","b","b"],        expected: true),
            (input: ["b","b","b","b"],    expected: true),
        ])

        // ── FOLLOW sets sanity check ──
        separator("FOLLOW sets")
        for grammar in [(gamma1, "Γ₁"), (gamma2, "Γ₂"), (gamma3, "Γ₃")] {
            let follow = grammar.0.followSets()
            print("  \(grammar.1):")
            for (nt, fs) in follow.sorted(by: { $0.key < $1.key }) {
                print("    FOLLOW(\(nt)) = {\(fs.sorted().joined(separator: ", "))}")
            }
        }

        separator("Done")
    }
}
