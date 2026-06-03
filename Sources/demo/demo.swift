// main.swift  —  Demo for the Earley Table Traversing Parser
//
// Reproduces the three example grammars used throughout
// Scott & Johnstone, "Earley Table Traversing Parser",
// Science of Computer Programming 247 (2026) 103335.
//
//   Γ₁: S ::= A S b | a       A ::= a A | ε
//   Γ₂: S ::= B B S a | b b b  B ::= b b B | ε
//   Γ₃: S ::= S S S | S S | b   (highly ambiguous)

import ArgumentParser
import Foundation
import Earley_TableParser
import Grammar

// MARK: - Grammar construction helpers

/// Convenience: terminal symbol from a plain string.
func T(_ s: String) -> Symbol { .terminal(Terminal(string: s)) }
/// Convenience: nonterminal symbol.
func N(_ s: String) -> Symbol { .nonTerminal(NonTerminal(name: s)) }
/// Convenience: nonterminal.
func NT(_ s: String) -> NonTerminal { NonTerminal(name: s) }

// MARK: - Γ₁  (Section 2.3)
//   S ::= A S b | a
//   A ::= a A | ε

let gamma1 = Grammar(
    productions: [
        Production(goal: NT("S"), rule: [N("A"), N("S"), T("b")]),
        Production(goal: NT("S"), rule: [T("a")]),
        Production(goal: NT("A"), rule: [T("a"), N("A")]),
        Production(goal: NT("A"), rule: []),     // ε-production
    ],
    start: NT("S"),
    lexicalTokens: [:]
)

// MARK: - Γ₂  (Section 4.3 / 5.1 / 6.3)
//   S ::= B B S a | b b b
//   B ::= b b B | ε

let gamma2 = Grammar(
    productions: [
        Production(goal: NT("S"), rule: [N("B"), N("B"), N("S"), T("a")]),
        Production(goal: NT("S"), rule: [T("b"), T("b"), T("b")]),
        Production(goal: NT("B"), rule: [T("b"), T("b"), N("B")]),
        Production(goal: NT("B"), rule: []),     // ε-production
    ],
    start: NT("S"),
    lexicalTokens: [:]
)

// MARK: - Γ₃  (Section 5.1 — highly ambiguous)
//   S ::= S S S | S S | b

let gamma3 = Grammar(
    productions: [
        Production(goal: NT("S"), rule: [N("S"), N("S"), N("S")]),
        Production(goal: NT("S"), rule: [N("S"), N("S")]),
        Production(goal: NT("S"), rule: [T("b")]),
    ],
    start: NT("S"),
    lexicalTokens: [:]
)

// MARK: - Display helpers

func separator(_ title: String) {
    print("\n" + String(repeating: "═", count: 70))
    print("  \(title)")
    print(String(repeating: "═", count: 70))
}

func printNFAStates(nfa: EarleyNFA, title: String) {
    separator("NFA States — \(title)")
    for (i, state) in nfa.states.enumerated() {
        let coreTag = nfa.isCore(i) ? " [core]" : ""
        print("  G_\(i)\(coreTag):")
        for slot in state.sorted(by: { $0.description < $1.description }) {
            print("    \(slot)")
        }
    }
}

// MARK: - Test runners

func testRecogniser(grammar: Grammar, name: String,
                    cases: [(input: [String], expected: Bool)]) {
    separator("Recogniser — \(name)")
    let nfa   = buildEarleyNFA(grammar: grammar)
    let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
    print("NFA states: \(nfa.stateCount)")
    var pass = 0
    for (tokens, expected) in cases {
        let got    = recET(table: table, input: tokens)
        let ok     = got == expected
        let mark   = ok ? "✓" : "✗ FAIL"
        let input  = tokens.isEmpty ? "ε" : "\"\(tokens.joined())\""
        print("  recET(\(input)) → \(got) [expected \(expected)] \(mark)")
        if ok { pass += 1 }
    }
    print("  \(pass)/\(cases.count) passed")
}

func testParser(grammar: Grammar, name: String,
                cases: [(input: [String], expected: Bool)]) {
    separator("Parser — \(name)")
    let nfa     = buildEarleyNFA(grammar: grammar)
    let slTable = buildSLParseTable(nfa: nfa, grammar: grammar)
    print("NFA states: \(nfa.stateCount)")
    var pass = 0
    for (tokens, expected) in cases {
        let result = simpleET(table: slTable, input: tokens)
        let ok     = result.accepted == expected
        let mark   = ok ? "✓" : "✗ FAIL"
        let input  = tokens.isEmpty ? "ε" : "\"\(tokens.joined())\""
        print("  simpleET(\(input)) → \(result.accepted) [expected \(expected)] \(mark)")
        print("    BSR elements: \(result.bsrSet.count)  ambiguous: \(result.hasAmbiguity)")
        // Print Earley sets for short inputs.
        if tokens.count <= 3 {
            for (j, ej) in result.earleySets.enumerated() {
                let pairs = ej.sorted {
                    $0.state < $1.state || ($0.state == $1.state && $0.backIndex < $1.backIndex)
                }.map { "(\($0.state),\($0.backIndex))" }
                print("    𝔼_\(j) = { \(pairs.joined(separator: ", ")) }")
            }
        }
        if ok { pass += 1 }
    }
    print("  \(pass)/\(cases.count) passed")
}

// MARK: - Main command

@main
struct Demo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        abstract: "Earley Table Traversing Parser — Scott & Johnstone (2026)"
    )

    @Flag(name: .shortAndLong, help: "Also print NFA state tables")
    var nfa: Bool = false

    mutating func run() throws {
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║   Earley Table Traversing Parser  —  Scott & Johnstone (2026)    ║")
        print("║   Science of Computer Programming 247, 103335                    ║")
        print("╚══════════════════════════════════════════════════════════════════╝")

        // ── Γ₁ ──────────────────────────────────────────────────────────────
        if nfa { printNFAStates(nfa: buildEarleyNFA(grammar: gamma1), title: "Γ₁") }

        testRecogniser(grammar: gamma1, name: "Γ₁  S::=ASb|a  A::=aA|ε", cases: [
            (["a"],                   true),
            (["a","b"],               true),   // A→ε, so S→ASb with S→a
            (["a","a","b"],           true),   // paper example
            (["a","a","a","b","b"],   true),
            (["b"],                   false),
            (["a","a"],               false),
        ])

        testParser(grammar: gamma1, name: "Γ₁", cases: [
            (["a"],         true),
            (["a","b"],     true),
            (["a","a","b"], true),
            (["b"],         false),
        ])

        // ── Γ₂ ──────────────────────────────────────────────────────────────
        if nfa { printNFAStates(nfa: buildEarleyNFA(grammar: gamma2), title: "Γ₂") }

        testRecogniser(grammar: gamma2, name: "Γ₂  S::=BBSa|bbb  B::=bbB|ε", cases: [
            (["b","b","b"],       true),
            (["b","b","b","a"],   true),   // B→ε,ε; S→BBSa
            (["b","b"],           false),
            (["b"],               false),
        ])

        testParser(grammar: gamma2, name: "Γ₂", cases: [
            (["b","b","b"],       true),
            (["b","b","b","a"],   true),
            (["b"],               false),
        ])

        // ── Γ₃ ──────────────────────────────────────────────────────────────
        if nfa { printNFAStates(nfa: buildEarleyNFA(grammar: gamma3), title: "Γ₃") }

        testRecogniser(grammar: gamma3, name: "Γ₃  S::=SSS|SS|b  (ambiguous)", cases: [
            (["b"],               true),
            (["b","b"],           true),
            (["b","b","b"],       true),   // §5.1 example
            (["b","b","b","b"],   true),
            (["a"],               false),
        ])

        testParser(grammar: gamma3, name: "Γ₃ (ambiguous)", cases: [
            (["b"],               true),
            (["b","b"],           true),
            (["b","b","b"],       true),
            (["b","b","b","b"],   true),
        ])

        // ── FOLLOW sets ──────────────────────────────────────────────────────
        separator("FOLLOW sets")
        for (g, name) in [(gamma1,"Γ₁"),(gamma2,"Γ₂"),(gamma3,"Γ₃")] {
            let follow = g.followSets()
            print("  \(name):")
            for (nt, fs) in follow.sorted(by: { $0.key.name < $1.key.name }) {
                let syms = fs.map(\.description).sorted().joined(separator: ", ")
                print("    FOLLOW(\(nt.name)) = { \(syms) }")
            }
        }

        separator("Done  ✓")
    }
}
