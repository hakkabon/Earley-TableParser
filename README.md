# Earley Table Traversing Parser

A Swift implementation of the Earley Table Traversing Parser algorithm developed by **Scott & Johnstone**.

> **Scott & Johnstone**, *"Earley Table Traversing Parsers"*,  
> Science of Computer Programming **247** (2026) 103335  
> https://doi.org/10.1016/j.scico.2025.103335

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)  
[![Platforms](https://img.shields.io/badge/platforms-macOS%2011%20%7C%20iOS%2014-blue.svg)](https://developer.apple.com/swift/)  
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)  

---

## Overview

This library implements a fully general context-free parser that handles **any** context-free grammar — including ambiguous, left-recursive, and ε-containing grammars — and produces a **Shared Packed Parse Forest (SPPF)** representing all parse derivations simultaneously.

The distinguishing features of the algorithm relative to classical Earley are:

- **Pre-computed tables** replace the on-the-fly slot generation of classical Earley, giving practical speedups of 2–3× on large grammars (the paper reports competitive performance with their fastest LR-style general parser).
- **Binary Subtree Representation (BSR)** sets provide a compact, set-based representation of all derivations that can be pre-computed in parts and stored in the table.
- **SLR(1) and extended lookahead** modes reduce unnecessary work without limiting the class of grammars that can be recognised.
- **Algorithmic simplicity**: the core of `parseET()` is eight lines of pseudocode (Section 7.3 of the paper).

---

## Architecture

```
Grammar (context-free)
       │
       ▼
  buildEarleyNFA()
       │  produces Earley NFA  G₀ … G_q
       │  each state is an entailment-closed set of grammar slots
       ▼
  buildSLParseTable()        buildELParseTable()
  (simple lookahead)         (extended lookahead)
       │                            │
       │  𝒯_Γ^SL(p, x) =            │  𝒯_Γ^EL(i, x) =
       │    (m, A_{p,x}, χ₁, χ₂)    │    (h, χ₁, χ₂)
       │                            │  + SELECT(i), rLHS(i) per state
       ▼                            ▼
  simpleET(table:input:)     parseET(table:input:)
       │                            │
       └────────────┬───────────────┘
                    │  produces
                    ▼
            ParseResult
            ├── accepted: Bool
            ├── bsrSet: Set<BSRElement>   (packed derivations)
            ├── earleySets: [Set<EarleyPair>]
            └── sppfGraph: SPPFGraph      (Shared Packed Parse Forest)
                    │
                    ▼
             EarleyTableParser  (public facade)
             ├── syntaxTree(for:)       → ParseTree   (one tree)
             └── allSyntaxTrees(for:)   → [ParseTree] (all trees)
```

---

## Quick Start

```swift
import Earley_TableParser
import Grammar

// 1. Define a grammar
let grammar = Grammar(
    productions: [
        Production(goal: NonTerminal(name: "S"), rule: [
            .nonTerminal(NonTerminal(name: "A")),
            .nonTerminal(NonTerminal(name: "S")),
            .terminal(Terminal(string: "b"))
        ]),
        Production(goal: NonTerminal(name: "S"), rule: [
            .terminal(Terminal(string: "a"))
        ]),
        Production(goal: NonTerminal(name: "A"), rule: [
            .terminal(Terminal(string: "a")),
            .nonTerminal(NonTerminal(name: "A"))
        ]),
        Production(goal: NonTerminal(name: "A"), rule: [])   // A → ε
    ],
    start: NonTerminal(name: "S"),
    lexicalTokens: [:]
)

// 2. Create a parser (tables pre-computed once at init time)
let parser = EarleyTableParser(grammar: grammar)

// 3a. Get one parse tree (DeterministicParser)
let tree = try parser.syntaxTree(for: "a a b")

// 3b. Get all parse trees (GeneralizedParser — useful for ambiguous grammars)
let allTrees = try parser.allSyntaxTrees(for: "a a b")

// 3c. Get the raw result (BSR set + SPPF graph)
let result = try parser.parse("a a b")
print("BSR elements: \(result.bsrSet.count)")
print("Ambiguous: \(result.hasAmbiguity)")

// 4. Use the recogniser only (fastest, no BSR/SPPF)
print("Accepted: \(parser.recognizes("a a b"))")
```

---

## Key Concepts

### Grammar Slots

A **grammar slot** `X ::= α · β` (also called an LR item) identifies a position inside a production rule. The dot `·` separates the part already matched (`α`) from the part still to be matched (`β`). Every production `X ::= γ` of length n gives n+1 slots.

### Earley NFA

The Earley NFA is a pre-computed finite automaton whose states are **entailment-closed** sets of grammar slots. Two operations build it:

- **`calls(M)`** — closes a set M of slots under *left-null calls*: if `X ::= α · Y β ∈ M` and `α ⟹* ε`, all slots `Y ::= ω · γ` where `ω ⟹* ε` are added (transitively).
- **`move(M, x)`** — advances every slot in M whose next symbol is `x`, then closes under `calls`.

The result is an NFA `G₀, G₁, …, G_q` similar in spirit to LR(0) DFA states, but constructed without determinisation. `G₀` is the start state.

### Parse Tables

The pre-computed tables replace the per-parse slot construction of classical Earley with simple array lookups.

#### SL Table  `𝒯_Γ^SL`

Each entry `𝒯_Γ^SL(p, x) = (m, A_{p,x}, χ₁, χ₂)` where:

| Field | Meaning |
|---|---|
| `m` | Next NFA state after consuming `x` (or `⊥`) |
| `A_{p,x}` | SLR(1) completer set: nonterminals `Y` with `Y ::= γ· ∈ G_p` and `x ∈ FOLLOW(Y)` |
| `χ₁` | `m(G_p, x)`: BSR grammar components for the direct transition on `x` |
| `χ₂` | `em(G_p, x)`: BSR components for nullable contributions |

#### EL Table  `𝒯_Γ^EL`

The extended-lookahead table replaces `A_{p,x}` with two per-state sets:

| Field | Meaning |
|---|---|
| `SELECT(p)` | Terminals `t` such that `G_p` contains `μ · ν` with `ν ⟹* tv'`, or `ν ⟹* ε` and `t ∈ FOLLOW(Y)` |
| `rLHS(p)` | Nonterminals `Y` with a complete item `Y ::= γ· ∈ G_p` |

`SELECT` is strictly more precise than FOLLOW: it guards both the completer and the scanner step, eliminating spurious actions on grammars with hidden left recursion.

### BSR Sets

A **BSR element** `(Ω, i, k, j)` represents a binarised derivation subtree:

- `Ω` is either a complete production `X ::= γ` or a left-prefix `δ` of a production rhs.
- `(i, j)` are the left and right input extents.
- `k` is the *pivot*: the split point between the two halves of the binary tree.

The BSR set is built incrementally during parsing by the `ADD()` function from the pre-computed `χ₁` and `χ₂` sets in the table. Pre-computation is what gives the algorithm its efficiency advantage over classical Earley.

### SPPF

The **Shared Packed Parse Forest** is an efficient graph representation of all derivation trees. It uses four node types:

| Type | Represents |
|---|---|
| `symbol(label, left, right)` | A nonterminal spanning `[left, right)` |
| `leaf(label, left, right)` | A terminal token at position `left` |
| `intermediate(label, left, right)` | A partial (binarised) rhs prefix |
| `packed(label, pivot)` | One specific derivation at a given split point |

Symbol and intermediate nodes with **multiple packed children** represent ambiguity: each packed child is an alternative derivation.

---

## Algorithms

### `recET()` — Recogniser (Section 5.2)

The fastest mode. Uses the recogniser table `𝒯_Γ` (no BSR components) and returns only accept/reject.

```
recET(𝒯_Γ, a₁…aₙ):
  𝔼₀ = R₀ = {(0, 0)}
  for j = 0 to n:
    while Rⱼ ≠ ∅:
      remove (p, k) from Rⱼ
      if k ≠ j:                                    // completer
        for X ∈ A_{p, aⱼ₊₁}:
          for (h, i) ∈ 𝔼ₖ: ADD(h, X, i, j)
      ADD(p, ε, j, j)                              // ε-transition
      if j < n: ADD(p, aⱼ₊₁, k, j+1)             // scanner
  accept iff some (p, 0) ∈ 𝔼ₙ with G_p accepting
```

### `simpleET()` — SL Parser (Section 7.1.1)

Extends `recET()` by building the BSR set. `ADD()` now takes a pivot `k` and populates `Υ` from `χ₁` and `χ₂`.

### `parseET()` — EL Parser (Section 7.3)

Uses the EL table and replaces `A_{p, aⱼ₊₁}` with `rLHS(p)` guarded by `aⱼ₊₁ ∈ SELECT(p)`. The scanner is similarly guarded. This eliminates false completions on grammars where the FOLLOW approximation is too coarse.

---

## Public API

### `EarleyTableParser`

```swift
public final class EarleyTableParser {

    // Pre-computed components (available for inspection)
    public let grammar:  Grammar
    public let nfa:      EarleyNFA
    public let slTable:  SLParseTable
    public let elTable:  ELParseTable

    // Select algorithm: false = SL (default), true = EL
    public var useExtendedLookahead: Bool

    public init(grammar: Grammar, useExtendedLookahead: Bool = false)

    // Parse pre-tokenised input directly
    public func parse(tokens: [String]) throws -> ParseResult
}
```

### `DeterministicParser` (one tree)

```swift
extension EarleyTableParser: DeterministicParser {
    public func syntaxTree(for string: String) throws -> ParseTree
    public func recognizes(_ string: String) -> Bool
}
```

### `GeneralizedParser` (all trees)

```swift
extension EarleyTableParser: GeneralizedParser {
    public func parse(_ string: String) throws -> ParseResult
    public func allSyntaxTrees(for string: String) throws -> [ParseTree]
}
```

### `ParseResult`

```swift
public struct ParseResult {
    public let accepted:   Bool
    public let bsrSet:     Set<BSRElement>
    public let earleySets: [Set<EarleyPair>]
    public let sppfGraph:  SPPFGraph?      // non-nil after EarleyTableParser.parse()
    public var hasAmbiguity: Bool
}
```

### Low-level free functions

These are available for embedding in larger systems that manage their own tables.

```swift
// NFA & table construction
func buildEarleyNFA(grammar: Grammar) -> EarleyNFA
func buildRecogniserTable(nfa: EarleyNFA, grammar: Grammar) -> RecogniserTable
func buildSLParseTable(nfa: EarleyNFA, grammar: Grammar) -> SLParseTable
func buildELParseTable(nfa: EarleyNFA, grammar: Grammar) -> ELParseTable

// Parsing
func recET(table: RecogniserTable, input: [String]) -> Bool
func simpleET(table: SLParseTable, input: [String]) -> ParseResult
func parseET(table: ELParseTable, input: [String]) -> ParseResult

// SPPF construction
func buildSPPF(from bsrSet: Set<BSRElement>, grammar: Grammar, tokens: [String]) -> SPPFGraph

// Debugging
func extractDerivation(from bsrSet: Set<BSRElement>, grammar: Grammar, tokens: [String]) -> String?
```

---

## Bugs Fixed

The following issues were corrected relative to the initial implementation:

1. **`simpleET()` initialisation** — the seed pair `(0, 0)` must pass through the full main loop so that the ε-transition of state 0 is processed and any BSR elements from `χ₁`/`χ₂` of that first transition are recorded. Previously the pair was inserted directly, bypassing `ADD()`.

2. **`bsrSetIsAmbiguous` false positives** — the heuristic was counting prefix BSR elements, which appear even in unambiguous parses. Fixed to count only complete `production` elements, and to require a differing pivot, not merely a second occurrence.

3. **`buildSPPF` multi-symbol left child** — productions with more than one symbol on the rhs were silently dropping the left child. Fixed to always create an intermediate SPPF node spanning `[leftExtent…pivot]`.

4. **Intermediate node dot position** — intermediate nodes were labelled with `syms.count - 1` as the dot position. The correct value is the *prefix length* (number of symbols already consumed), which for a prefix of length k is `k`, not `k - 1`.

5. **`reconstructChildren` incomplete** — multi-symbol productions returned a bare string extent rather than recursing into the BSR. Replaced with a full recursive descent over the BSR set that handles any production shape.

---

## Improvements

- **`EarleyTableParser` facade** — previously, the only API was free functions. The new `EarleyTableParser` class pre-computes both tables at `init` time and conforms to `DeterministicParser` and `GeneralizedParser`.
- **`allSyntaxTrees(for:)`** — full combinatorial enumeration of every distinct derivation tree via cross-product expansion over packed SPPF nodes. De-duplicates by structural equality.
- **`parseET()` + EL table** — extended-lookahead algorithm from Section 7.3 is now fully implemented. Toggle with `useExtendedLookahead = true`.
- **`sppfGraph` always populated** — `ParseResult.sppfGraph` is always non-nil after a call to `EarleyTableParser.parse()`.
- **`hasAmbiguity` now SPPF-based** — when the SPPF is available, ambiguity is detected by counting packed-node children rather than using the BSR heuristic.

---

## Dependencies

| Package | Purpose |
|---|---|
| [hakkabon/Grammar](https://github.com/hakkabon/Grammar) | `Grammar`, `Production`, `NonTerminal`, `Terminal`, `Symbol` types |
| [hakkabon/GrammarTokenizer](https://github.com/hakkabon/GrammarTokenizer) | Lexical tokenization |
| [hakkabon/GrammarDiagram](https://github.com/hakkabon/GrammarDiagram) | Grammar diagram export |

---

## Running the Tests

```bash
swift test
```

## Running the Demo

```bash
swift run demo          # run all three paper examples
swift run demo --nfa    # also print NFA state tables
```

---

## References

- Scott, E. & Johnstone, A. (2026). *Earley Table Traversing Parsers*. Science of Computer Programming **247**, 103335. https://doi.org/10.1016/j.scico.2025.103335
- Earley, J. (1970). An efficient context-free parsing algorithm. *Communications of the ACM* **13**(2), 94–102.
- Tomita, M. (1987). An efficient augmented-context-free parsing algorithm. *Computational Linguistics* **13**, 31–46.
- Scott, E. & Johnstone, A. (2013). BSR parsing. *Electronic Notes in Theoretical Computer Science* **253**, 17–51.
