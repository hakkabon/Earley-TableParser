# Earley Table Traversing Parser

A Swift implementation of the Earley Table Traversing Parser algorithm from:

**Scott & Johnstone**, *"Earley Table Traversing Parser"*, Science of Computer Programming 247 (2026), https://doi.org/10.1016/j.scico.2025.103335

## Overview

This library implements a robust, generalised Earley parser that:

- **Handles any context-free grammar**, including ambiguous and left-recursive grammars
- **Produces a Shared Packed Parse Forest (SPPF)** representing all possible parse trees
- **Uses Binary Subset Representation (BSR)** internally to efficiently pack derivations
- **Extracts specific syntax trees** on demand from the SPPF
- **Detects ambiguity** by counting distinct derivations for the same input

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Earley Table Parser                          │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │
│  │   Grammar    │→ │   Earley NFA │→ │  Parse Table │               │
│  │ (context-free│  │  (states G₀  │  │  (SL table)  │               │
│  │    grammar)  │  │   … G_q)     │  │              │               │
│  └──────────────┘  └──────────────┘  └──────────────┘               │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    simpleET() / recET()                     │    │
│  │                    (parser / recogniser)                    │    │
│  │  Input: tokens ────────→  Earley sets 𝔼₀ … 𝔼_n              │    │
│  │                           BSR set Υ                         │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    Output:                                  │    │
│  │  • Accept/reject decision                                   │    │
│  │  • BSR set (packed derivations)                             │    │
│  │  • SPPF graph (Shared Packed Parse Forest)                  │    │
│  │  • Ambiguity detection                                      │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```swift
import Earley_TableParser
import Grammar

// Define a grammar
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
        Production(goal: NonTerminal(name: "A"), rule: [])  // ε
    ],
    start: NonTerminal(name: "S"),
    lexicalTokens: [:]
)

// Build parser components
let nfa = buildEarleyNFA(grammar: grammar)
let table = buildSLParseTable(nfa: nfa, grammar: grammar)

// Parse input
let tokens = ["a", "a", "b"]
let result = simpleET(table: table, input: tokens)

if result.accepted {
    print("Input accepted!")
    print("BSR elements: \(result.bsrSet.count)")
    print("Ambiguous: \(result.hasAmbiguity)")
    
    // Build SPPF for derivation extraction
    let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: tokens)
    
    // Extract a specific derivation
    let derivation = extractDerivation(from: result.bsrSet, grammar: grammar, tokens: tokens)
    print("Derivation: \(derivation ?? "N/A")")
}
```

## API Reference

### Core Functions

#### `buildEarleyNFA(grammar:)`
Construct the Earley NFA (state graph) for a grammar.

```swift
let nfa = buildEarleyNFA(grammar: myGrammar)
print("NFA states: \(nfa.stateCount)")
```

#### `buildRecogniserTable(nfa:grammar:)`
Build the recogniser table used by `recET()` for quick accept/reject decisions.

```swift
let table = buildRecogniserTable(nfa: nfa, grammar: grammar)
let accepted = recET(table: table, input: ["a", "b", "c"])
```

#### `buildSLParseTable(nfa:grammar:)`
Build the SL (Simple Lookahead) parse table for full parsing with BSR generation.

```swift
let slTable = buildSLParseTable(nfa: nfa, grammar: grammar)
let result = simpleET(table: slTable, input: ["a", "b", "c"])
```

#### `recET(table:input:)`
The recogniser from Section 5.2 of Scott & Johnstone (2026). Returns `true` if the input is in the grammar's language.

```swift
let accepted = recET(table: table, input: ["a", "b"])
```

#### `simpleET(table:input:)`
The full parser from Section 7.1.1. Returns a `EarleyParseResult` with BSR set and Earley sets.

```swift
let result = simpleET(table: table, input: ["a", "b", "c"])
if result.accepted {
    let bsr = result.bsrSet  // All derivations packed as BSR elements
}
```

#### `buildSPPF(from:grammar:tokens:)`
Construct an SPPF graph from a BSR set for efficient storage and derivation extraction.

```swift
let sppf = buildSPPF(from: result.bsrSet, grammar: grammar, tokens: tokens)
```

#### `extractDerivation(from:grammar:tokens:)`
Extract a single derivation tree as a readable string representation.

```swift
if let derivation = extractDerivation(from: bsrSet, grammar: grammar, tokens: tokens) {
    print(derivation)
    // Output: "(S → (A → a) (S → a b))"
}
```

### Data Types

#### `EarleyParseResult`
Result of `simpleET()`:

- `accepted: Bool` — Whether the input was accepted
- `bsrSet: Set<BSRElement>` — All binarised derivation subtrees
- `earleySets: [Set<EarleyPair>]` — The Earley sets 𝔼₀ … 𝔼_n
- `sppfGraph: SPPFGraph?` — The SPPF graph (if constructed)
- `hasAmbiguity: Bool` — True if multiple distinct derivations exist

#### `BSRElement`
Binary Subset Representation element `(Ω, i, k, j)` representing a binarised derivation:

- `omega: BSRComponent` — The grammar component (production or prefix)
- `leftExtent: Int` — Start position in input
- `pivot: Int` — Split point for binarisation
- `rightExtent: Int` — End position in input

#### `SPPFGraph`
Shared Packed Parse Forest graph. Nodes include:

- `.leaf` — Terminal tokens
- `.symbol` — Non-terminal symbol nodes
- `.intermediate` — Partial derivation nodes
- `.packed` — Specific production applications

### Grammar Definition

This library uses the `Grammar` package from [`hakkabon/Grammar`](https://github.com/hakkabon/Grammar).

```swift
import Grammar

// Terminal symbols
let a = .terminal(Terminal(string: "a"))
let b = .terminal(Terminal(string: "b"))

// Non-terminal symbols
let S = .nonTerminal(NonTerminal(name: "S"))
let A = .nonTerminal(NonTerminal(name: "A"))

// Epsilon (empty) production
let eps = .terminal(.meta(.eps))

// Define production rules
let productions: [Production] = [
    Production(goal: NonTerminal(name: "S"), rule: [A, S, b]),
    Production(goal: NonTerminal(name: "S"), rule: [a]),
    Production(goal: NonTerminal(name: "A"), rule: [a, A]),
    Production(goal: NonTerminal(name: "A"), rule: [])  // A → ε
]

// Create grammar
let grammar = Grammar(
    productions: productions,
    start: NonTerminal(name: "S"),
    lexicalTokens: [:]
)
```

## Examples

### Example 1: Simple Grammar Γ₁
**Grammar**: `S ::= A S b | a` , `A ::= a A | ε`

```swift
let gamma1 = Grammar(
    productions: [
        Production(goal: NonTerminal(name: "S"), rule: [.nonTerminal(NonTerminal(name: "A")), .nonTerminal(NonTerminal(name: "S")), .terminal(Terminal(string: "b"))]),
        Production(goal: NonTerminal(name: "S"), rule: [.terminal(Terminal(string: "a"))]),
        Production(goal: NonTerminal(name: "A"), rule: [.terminal(Terminal(string: "a")), .nonTerminal(NonTerminal(name: "A"))]),
        Production(goal: NonTerminal(name: "A"), rule: [])
    ],
    start: NonTerminal(name: "S"),
    lexicalTokens: [:]
)

let nfa = buildEarleyNFA(grammar: gamma1)
let table = buildSLParseTable(nfa: nfa, grammar: gamma1)
let result = simpleET(table: table, input: ["a", "a", "b"])

// result.accepted == true
// parses "aab" as: A→a, S→a, S→ASb with A→ε
```

### Example 2: Ambiguous Grammar Γ₃
**Grammar**: `S ::= S S S | S S | b`

```swift
let gamma3 = Grammar(
    productions: [
        Production(goal: NonTerminal(name: "S"), rule: [
            .nonTerminal(NonTerminal(name: "S")),
            .nonTerminal(NonTerminal(name: "S")),
            .nonTerminal(NonTerminal(name: "S"))
        ]),
        Production(goal: NonTerminal(name: "S"), rule: [
            .nonTerminal(NonTerminal(name: "S")),
            .nonTerminal(NonTerminal(name: "S"))
        ]),
        Production(goal: NonTerminal(name: "S"), rule: [.terminal(Terminal(string: "b"))])
    ],
    start: NonTerminal(name: "S"),
    lexicalTokens: [:]
)

let nfa = buildEarleyNFA(grammar: gamma3)
let table = buildSLParseTable(nfa: nfa, grammar: gamma3)
let result = simpleET(table: table, input: ["b", "b", "b"])

// result.accepted == true
// result.hasAmbiguity == true (many different parse trees)
// result.bsrSet.count > 1 (multiple derivations)
```

### Example 3: Grammar with Epsilon
**Grammar**: `S ::= A b | ε` , `A ::= a | ε`

```swift
let epsGrammar = Grammar(
    productions: [
        Production(goal: NonTerminal(name: "S"), rule: [.nonTerminal(NonTerminal(name: "A")), .terminal(Terminal(string: "b"))]),
        Production(goal: NonTerminal(name: "S"), rule: []),
        Production(goal: NonTerminal(name: "A"), rule: [.terminal(Terminal(string: "a"))]),
        Production(goal: NonTerminal(name: "A"), rule: [])
    ],
    start: NonTerminal(name: "S"),
    lexicalTokens: [:]
)

let nfa = buildEarleyNFA(grammar: epsGrammar)
let table = buildSLParseTable(nfa: nfa, grammar: epsGrammar)

// Parse empty string
let emptyResult = simpleET(table: table, input: [])
// emptyResult.accepted == true

// Parse "b"
let bResult = simpleET(table: table, input: ["b"])
// bResult.accepted == true
```

## Algorithm Details

### 1. Earley NFA Construction (Section 4.3)
The NFA is built using Breadth-First Search starting from `G₀ = calls(S_LNcall)`, where:
- `calls(M)` computes the smallest set of slots closed under left-null-call transitions
- `move(M, x)` computes states reachable by consuming symbol x

### 2. Recogniser Table Traversal (Section 5.2)
The `recET()` algorithm uses three actions per Earley set:
1. **Completer** (k ≠ j): Propagate completed non-terminals using FOLLOW lookahead
2. **ε-transition**: Handle epsilon productions
3. **Scanner** (j < n): Match next input token

### 3. Simple Lookahead Parser (Section 7.1.1)
The `simpleET()` extension adds BSR generation:
- Maintains global BSR set Υ alongside Earley sets
- Populates Υ with BSR elements `(Ω, i, k, j)` during ADD operations
- χ₁ contains direct transition components
- χ₂ contains ε-related nullable contributions

### 4. Binary Subset Representation
BSR elements pack derivations binarised as:
- `.production(Production)` — Complete production applications
- `.prefix(NonTerminal, [Symbol])` — Partial production prefixes

### 5. Shared Packed Parse Forest
SPPF graphs store all derivations compactly using:
- **Packed nodes** for alternative productions
- **Intermediate nodes** for shared prefixes
- **Symbol nodes** for non-terminals
- **Leaf nodes** for terminal tokens

## Testing

Run the test suite:

```bash
swift test
```

Run the demo executable:

```bash
swift run demo
```

The demo exercises all example grammars from the paper (Γ₁, Γ₂, Γ₃) and prints:
- NFA state tables
- Recogniser results
- Parser results with BSR element counts
- FOLLOW set analysis
- Ambiguity detection

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/hakkabon/Grammar.git", branch: "main"),
    .package(url: "https://github.com/your-username/Earley-TableParser.git", from: "1.0.0")
]
```

Then add `Earley-TableParser` to your target's dependencies.

## License

MIT License. See `LICENSE` file.

## References

1. **Scott & Johnstone (2026)** - *Earley Table Traversing Parser*, Science of Computer Programming 247, 103335. https://doi.org/10.1016/j.scico.2025.103335

2. **Tomita (1987)** - *An Efficient Parsing Algorithm for Arbitrary Context-Free Grammars*

3. **Perfect & Scott (2007)** - *Binarisation of Syntax Trees for Efficient Storage and Extraction*

4. **Hakkabon Grammar** - https://github.com/hakkabon/Grammar
