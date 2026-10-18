import Testing
@testable import Earley_TableParser
import Grammar
import Parser

private struct OracleItem: Hashable {
    let production: Int
    let dot: Int
    let origin: Int
}

/// A deliberately direct, table-independent Earley recognizer used only as a
/// differential oracle. It shares Grammar's data model, but none of the NFA,
/// SELECT, FOLLOW, or table-traversal implementation under test.
private func classicalEarleyRecognizes(
    _ grammar: Grammar,
    tokens: [String]
) -> Bool {
    let productions = grammar.productions
    var chart = [Set<OracleItem>](repeating: [], count: tokens.count + 1)

    for index in productions.indices where productions[index].goal == grammar.start {
        chart[0].insert(OracleItem(production: index, dot: 0, origin: 0))
    }

    for position in chart.indices {
        var changed = true
        while changed {
            changed = false
            for item in Array(chart[position]) {
                let production = productions[item.production]
                if item.dot == production.rule.count {
                    for waiting in Array(chart[item.origin]) {
                        let waitingProduction = productions[waiting.production]
                        guard waiting.dot < waitingProduction.rule.count,
                              case .nonTerminal(let expected) = waitingProduction.rule[waiting.dot],
                              expected == production.goal else { continue }
                        changed = chart[position].insert(OracleItem(
                            production: waiting.production,
                            dot: waiting.dot + 1,
                            origin: waiting.origin)).inserted || changed
                    }
                    continue
                }

                switch production.rule[item.dot] {
                case .nonTerminal(let nonterminal):
                    for index in productions.indices
                    where productions[index].goal == nonterminal {
                        changed = chart[position].insert(OracleItem(
                            production: index,
                            dot: 0,
                            origin: position)).inserted || changed
                    }
                case .terminal(let terminal) where terminal.isEmpty:
                    changed = chart[position].insert(OracleItem(
                        production: item.production,
                        dot: item.dot + 1,
                        origin: item.origin)).inserted || changed
                case .terminal, .metaSymbol:
                    break
                }
            }
        }

        guard position < tokens.count else { continue }
        for item in chart[position] {
            let production = productions[item.production]
            guard item.dot < production.rule.count,
                  case .terminal(.string(let literal)) = production.rule[item.dot],
                  literal == tokens[position] else { continue }
            chart[position + 1].insert(OracleItem(
                production: item.production,
                dot: item.dot + 1,
                origin: item.origin))
        }
    }

    return chart[tokens.count].contains { item in
        let production = productions[item.production]
        return item.origin == 0 &&
            item.dot == production.rule.count &&
            production.goal == grammar.start
    }
}

private func boundedWords(_ alphabet: [String], through maximumLength: Int) -> [[String]] {
    var result: [[String]] = [[]]
    var frontier: [[String]] = [[]]
    for _ in 0..<maximumLength {
        frontier = frontier.flatMap { prefix in alphabet.map { prefix + [$0] } }
        result.append(contentsOf: frontier)
    }
    return result
}

private func generatedGrammars() -> [Grammar] {
    let s = NonTerminal(name: "S")
    let a = NonTerminal(name: "A")
    let b = NonTerminal(name: "B")
    let mandatory = [
        Production(goal: s, rule: [.nonTerminal(a)]),
        Production(goal: a, rule: [.terminal(Terminal(string: "a"))]),
        Production(goal: b, rule: [.terminal(Terminal(string: "b"))])
    ]
    let optional = [
        Production(goal: s, rule: [.terminal(Terminal(string: "b"))]),
        Production(goal: s, rule: [.nonTerminal(s), .terminal(Terminal(string: "b"))]),
        Production(goal: s, rule: [.nonTerminal(a), .nonTerminal(b)]),
        Production(goal: a, rule: []),
        Production(goal: a, rule: [.nonTerminal(b)]),
        Production(goal: b, rule: [.nonTerminal(a)])
    ]

    return (0..<(1 << optional.count)).map { mask in
        let selected = optional.indices.compactMap { index in
            mask & (1 << index) == 0 ? nil : optional[index]
        }
        return Grammar(
            productions: mandatory + selected,
            start: s,
            lexicalTokens: [:])
    }
}

private func indirectNullableGrammar() -> Grammar {
    Grammar(
        productions: [
            Production(goal: NonTerminal(name: "S"), rule: [.nonTerminal(NonTerminal(name: "A"))]),
            Production(goal: NonTerminal(name: "A"), rule: [.nonTerminal(NonTerminal(name: "B"))]),
            Production(goal: NonTerminal(name: "B"), rule: [])
        ],
        start: NonTerminal(name: "S"),
        lexicalTokens: [:])
}

private func hiddenLeftRecursiveGrammar() -> Grammar {
    Grammar(
        productions: [
            Production(goal: NonTerminal(name: "S"), rule: [
                .nonTerminal(NonTerminal(name: "A")),
                .terminal(Terminal(string: "a"))]),
            Production(goal: NonTerminal(name: "S"), rule: [
                .terminal(Terminal(string: "b"))]),
            Production(goal: NonTerminal(name: "A"), rule: [
                .nonTerminal(NonTerminal(name: "S"))]),
            Production(goal: NonTerminal(name: "A"), rule: [])
        ],
        start: NonTerminal(name: "S"),
        lexicalTokens: [:])
}

@Suite("Phase 23 — Earley table correctness")
struct EarleyTableConformanceTests {
    @Test("EL SELECT excludes terminals hidden behind a non-nullable prefix")
    func selectStopsAtNonNullablePrefix() {
        let s = NonTerminal(name: "S")
        let a = NonTerminal(name: "A")
        let grammar = Grammar(
            productions: [
                Production(goal: s, rule: [.nonTerminal(a)]),
                Production(goal: a, rule: [
                    .terminal(Terminal(string: "a")),
                    .terminal(Terminal(string: "b"))])
            ],
            start: s,
            lexicalTokens: [:])
        let nfa = buildEarleyNFA(grammar: grammar)
        let table = buildELParseTable(nfa: nfa, grammar: grammar)
        let select = table.info(state: 0)?.selectSet ?? []

        #expect(select.contains(.terminal(Terminal(string: "a"))))
        #expect(!select.contains(.terminal(Terminal(string: "b"))))
    }

    @Test("SL and EL agree with an independent Earley oracle on bounded grammars")
    func boundedDifferentialRecognition() {
        let inputs = boundedWords(["a", "b"], through: 3)

        for (grammarIndex, grammar) in generatedGrammars().enumerated() {
            let nfa = buildEarleyNFA(grammar: grammar)
            let sl = buildSLParseTable(nfa: nfa, grammar: grammar)
            let el = buildELParseTable(nfa: nfa, grammar: grammar)

            // Inputs are length ordered, so the first report is a bounded
            // minimal counterexample for this grammar.
            for tokens in inputs {
                let expected = classicalEarleyRecognizes(grammar, tokens: tokens)
                let simple = simpleET(table: sl, input: tokens).accepted
                let extended = parseET(table: el, input: tokens).accepted
                if expected != simple || expected != extended {
                    Issue.record("grammar #\(grammarIndex), minimal input \(tokens): oracle=\(expected), SL=\(simple), EL=\(extended)")
                    break
                }
            }
        }
    }

    @Test("Indirect nullable start and hidden left recursion match the oracle")
    func targetedRegressions() {
        let cases: [(Grammar, [[String]])] = [
            (indirectNullableGrammar(), [[], ["a"]]),
            (hiddenLeftRecursiveGrammar(), boundedWords(["a", "b"], through: 4))
        ]

        for (grammar, inputs) in cases {
            let nfa = buildEarleyNFA(grammar: grammar)
            let sl = buildSLParseTable(nfa: nfa, grammar: grammar)
            let el = buildELParseTable(nfa: nfa, grammar: grammar)
            for tokens in inputs {
                let expected = classicalEarleyRecognizes(grammar, tokens: tokens)
                #expect(simpleET(table: sl, input: tokens).accepted == expected)
                #expect(parseET(table: el, input: tokens).accepted == expected)
            }
        }
    }

    @Test("SL and EL export the same validated portable forests")
    func portableForestParity() throws {
        for grammar in [gamma1(), gamma2(), gamma3(), hiddenLeftRecursiveGrammar()] {
            let nfa = buildEarleyNFA(grammar: grammar)
            let sl = buildSLParseTable(nfa: nfa, grammar: grammar)
            let el = buildELParseTable(nfa: nfa, grammar: grammar)
            for tokens in boundedWords(["a", "b"], through: 3) {
                let simple = simpleET(table: sl, input: tokens)
                let extended = parseET(table: el, input: tokens)
                guard simple.accepted else { continue }

                let simpleForest = try buildSPPF(
                    from: simple.bsrSet, grammar: grammar, tokens: tokens).portableSnapshot()
                let extendedForest = try buildSPPF(
                    from: extended.bsrSet, grammar: grammar, tokens: tokens).portableSnapshot()
                #expect(simpleForest == extendedForest, "forest mismatch for \(tokens)")
            }
        }
    }

    @Test("EL construction and traversal are repeatable and production-order invariant")
    func deterministicAndOrderInvariant() {
        let grammar = hiddenLeftRecursiveGrammar()
        let reversed = Grammar(
            productions: Array(grammar.productions.reversed()),
            start: grammar.start,
            lexicalTokens: grammar.lexicalTokens)
        let inputs = boundedWords(["a", "b"], through: 4)

        let firstNFA = buildEarleyNFA(grammar: grammar)
        let firstTable = buildELParseTable(nfa: firstNFA, grammar: grammar)
        let secondNFA = buildEarleyNFA(grammar: grammar)
        let secondTable = buildELParseTable(nfa: secondNFA, grammar: grammar)
        let reversedNFA = buildEarleyNFA(grammar: reversed)
        let reversedTable = buildELParseTable(nfa: reversedNFA, grammar: reversed)

        for tokens in inputs {
            let first = parseET(table: firstTable, input: tokens)
            let second = parseET(table: secondTable, input: tokens)
            let permuted = parseET(table: reversedTable, input: tokens)
            #expect(first.accepted == second.accepted)
            #expect(first.bsrSet == second.bsrSet)
            #expect(first.accepted == permuted.accepted)
            #expect(first.bsrSet == permuted.bsrSet)
        }
    }

    @Test("Typed lookahead mode preserves the Boolean compatibility API")
    func typedLookaheadMode() {
        let typed = EarleyTableParser(grammar: gamma1(), lookahead: .extended)
        let compatibility = EarleyTableParser(
            grammar: gamma1(), useExtendedLookahead: true)
        #expect(typed.lookahead == .extended)
        #expect(typed.useExtendedLookahead)
        #expect(compatibility.lookahead == .extended)
        #expect(compatibility.useExtendedLookahead)
        #expect(EarleyTableParser(grammar: gamma1()).lookahead == .simple)
    }
}
