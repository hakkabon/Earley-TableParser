# Earley Table Traversing Parser

A Swift implementation of the Earley Table Traversing Parser algorithm from:

> **Scott & Johnstone**, *"Earley Table Traversing Parsers"*  
> Science of Computer Programming **247** (2026) 103335  
> <https://doi.org/10.1016/j.scico.2025.103335>

Fully general: handles any context-free grammar — ambiguous, left-recursive, ε-containing — and produces a Shared Packed Parse Forest (SPPF) that encodes all derivations simultaneously.

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
buildEarleyNFA()          ← computed once, O(|G|³) in grammar size
       │
       │  G₀ … G_q
       │  entailment-closed sets of grammar slots
       │
       ├──► buildSLParseTable()          buildELParseTable()
       │    𝒯_Γ^SL(p,x)=(m,A,χ₁,χ₂)    𝒯_Γ^EL(p,x)=(m,χ₁,χ₂)
       │    + SLR(1) lookahead A_{p,x}   + SELECT(p), rLHS(p) per state
       │
       ▼
simpleET(table:input:)    parseET(table:input:)
       │                        │
       └──────────┬─────────────┘
                  │   EarleyTableParseResult
                  │   ├── accepted: Bool
                  │   ├── bsrSet:  Set<BSR<NodeLabel>>
                  │   ├── earleySets: [Set<EarleyPair>]
                  │   └── sppfGraph: SPPFGraph<NodeLabel>?
                  │
                  ▼
         EarleyTableParser          (public facade)
         ├── DeterministicParser
         │   ├── syntaxTree(for:)    → ParseTree
         │   └── recognizes(_:)     → Bool
         └── GeneralizedParser
             ├── parse(_:)           → ParseResult<NodeLabel>
             └── allSyntaxTrees(for:) → [ParseTree]
```

The `Grammar`, `BSR`, `SPPFGraph`, `SPPFNode`, `ParseResult`, `DeterministicParser`, and `GeneralizedParser` types all come from the [hakkabon/Parser](https://github.com/hakkabon/Parser) module, which this package aligns with exactly.

---

## Quick Start

```swift
import Earley_TableParser
import Grammar
import Lexer

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

// 2. Create the parser (NFA + both tables pre-computed once at init)
let parser = EarleyTableParser(grammar: grammar)

// 3a. Check membership
print(parser.recognizes("a a b"))  // true

// 3b. One parse tree (DeterministicParser)
let tree = try parser.syntaxTree(for: "a a b")

// 3c. All parse trees (GeneralizedParser — useful for ambiguous grammars)
let trees = try parser.allSyntaxTrees(for: "a a b")

// 3d. Raw result: BSR set + SPPF graph
let result = try parser.parse("a a b")
print("BSR elements:", result.bsr.count)
print("Ambiguous:",    result.hasAmbiguity)

// 4. Pre-tokenised input bypasses the whitespace tokeniser
let rawResult = try parser.parse(tokens: ["a", "a", "b"])

// 5. Preferred parser boundary: consume any Lexer TokenStream directly.
// No tokenization is performed by the table parser.
let stream = TokenizerStream(source: "a a b")
let streamedResult = try parser.parse(stream: stream)

// 6. Switch to extended lookahead (Section 7.3)
parser.useExtendedLookahead = true
let elTree = try parser.syntaxTree(for: "a a b")
```

---

## Key Concepts

### Grammar Slots

A **grammar slot** `X ::= α · β` identifies a dot position inside a production (these are also called LR items in other frameworks). Every production of length n contributes n+1 slots. `NodeLabel` represents a slot with fields `(goal, symbols, position)`.

### Earley NFA

Built once from the grammar by computing two functions (Section 4.2):

- **`calls(M)`** — closes a set of slots under left-null calls: if `X ::= α·Yβ ∈ M` and `α ⟹* ε`, all slots `Y ::= ω·γ` where `ω ⟹* ε` are added transitively.
- **`move(M, x)`** — advances every slot in M whose next symbol is `x`, then closes under `calls`.

The BFS over reachable `move`-states produces the NFA states `G₀, G₁, … G_q`, analogous to LR(0) items but without determinisation.

### BSR Sets

A **BSR element** `(Ω, i, k, j)` represents a binarised derivation subtree: `Ω` is a `NodeLabel` (complete or partial), `(i,j)` are the input extents, and `k` is the pivot (binary split point). The type is `BSR<NodeLabel>` from the Parser module. Pre-computed sets `χ₁ = m(G_p, x)` and `χ₂ = em(G_p, x)` in the table mean the parser emits BSR elements with two array lookups per `ADD()` call.

### SL Parse Table — `𝒯_Γ^SL`

Each entry `𝒯_Γ^SL(p, x) = (m, A_{p,x}, χ₁, χ₂)`:

| Field | Meaning |
|---|---|
| `m` | Next NFA state after consuming `x` (or ⊥) |
| `A_{p,x}` | SLR(1) completer set: nonterminals `Y` with `Y ::= γ· ∈ G_p` and `x ∈ FOLLOW(Y)` |
| `χ₁` | `m(G_p, x)` — BSR components for the direct `x`-transition |
| `χ₂` | `em(G_p, x)` — BSR components for nullable contributions at the target |

Pattern terminals (regex, character range, string list) are matched via `resolveKey(forToken:)`, which maps a raw token to the column key its entry is stored under.

### EL Parse Table — `𝒯_Γ^EL` *(new in this revision)*

The extended-lookahead table replaces the per-(state,symbol) `A_{p,x}` with two **per-state** sets (Section 7.2–7.3):

| Field | Meaning |
|---|---|
| `SELECT(p)` | Terminals `t` such that `G_p` contains `μ·ν` with `ν ⟹* tv'` or (`ν ⟹* ε` and `t ∈ FOLLOW(Y)`) |
| `rLHS(p)` | Nonterminals `Y` with a complete item `Y ::= δ· ∈ G_p` |

`SELECT` is strictly more precise than FOLLOW: it prevents spurious completions on grammars with hidden left recursion (Section 7.2 of the paper). Table entries still hold `(m, χ₁, χ₂)`.

### SPPF

The **Shared Packed Parse Forest** is constructed by `buildSPPF(from:grammar:tokens:)` from the raw BSR set. It uses the `SPPFGraph<NodeLabel>` type from the Parser module. Ambiguity shows up as `.symbol` or `.intermediate` nodes with more than one `.packed` child. Tree extraction is handled by `SPPFGraph.buildParseTree` and `buildAllParseTrees` (from the Parser module's `TreeBuilder` extension).

---

## Algorithms

### `recET()` — Recogniser (Section 5.2)

Fastest mode. Uses the recogniser table with no BSR components; returns only accept/reject.

```
recET(𝒯_Γ, a₁…aₙ):
  𝔼₀ = R₀ = {(0,0)}
  for j = 0 to n:
    while Rⱼ ≠ ∅:
      (p,k) ← remove from Rⱼ
      if k ≠ j:                                       // completer
        for X ∈ A_{p, aⱼ₊₁}:
          for (h,i) ∈ 𝔼ₖ: ADD(h, X, i, j)
      ADD(p, ε, j, j)                                 // ε-transition
      if j < n: ADD(p, aⱼ₊₁, k, j+1)                // scanner
  accept iff (p,0) ∈ 𝔼ₙ for some accepting p
```

### `simpleET()` — SL Parser (Section 7.1.1)

Extends `recET()` with BSR construction. `ADD(p, x, i, k, j)` reads `χ₁`/`χ₂` from the SL table and inserts `BSR` elements into Υ before updating the Earley sets.

### `parseET()` — EL Parser (Section 7.3) *(new in this revision)*

Same control flow as `simpleET()` but uses the EL table and replaces `A_{p, aⱼ₊₁}` with `rLHS(p)` guarded by `aⱼ₊₁ ∈ SELECT(p)`. The scanner is similarly guarded:

```
parseET(𝒯_Γ^EL, SELECT, rLHS, a₁…aₙ):
  𝔼₀ = R₀ = {(0,0)}
  for j = 0 to n:
    while Rⱼ ≠ ∅:
      (p,k) ← remove from Rⱼ
      if k ≠ j and aⱼ₊₁ ∈ SELECT(p):               // EL completer guard
        for Y ∈ rLHS(p):
          for (h,i) ∈ 𝔼ₖ: ADD(h, Y, i, k, j)
      ADD(p, ε, j, j, j)                             // ε-transition
      if j < n and aⱼ₊₁ ∈ SELECT(p):               // EL scanner guard
        ADD(p, aⱼ₊₁, k, j, j+1)
  accept iff (p,0) ∈ 𝔼ₙ for some accepting p
```

---

## Public API

### `EarleyTableParser`

```swift
public final class EarleyTableParser {
    public let grammar:  Grammar
    public let nfa:      EarleyNFA
    public let slTable:  SLParseTable
    public let elTable:  ELParseTable
    public var useExtendedLookahead: Bool   // default: false
    public init(grammar: Grammar, useExtendedLookahead: Bool = false)

    // Core method (both SL and EL route through here)
    public func parse(tokens: [String]) throws -> EarleyTableParseResult

    // Parser-level entry point for LexerTokenStream, TokenizerStream, or any
    // other TokenStream implementation. Terminals and source ranges are
    // supplied by the stream.
    public func parse<S: TokenStream>(stream: S) throws -> ParseResult<NodeLabel>
}
```

### `DeterministicParser` conformance

```swift
extension EarleyTableParser: DeterministicParser {
    public func syntaxTree(for string: String) throws -> ParseTree
    public func recognizes(_ string: String) -> Bool   // default impl, never throws
}
```

### `GeneralizedParser` conformance

```swift
extension EarleyTableParser: GeneralizedParser {
    public typealias Label = NodeLabel
    public func parse(_ string: String) throws -> ParseResult<NodeLabel>
    public func allSyntaxTrees(for string: String) throws -> [ParseTree]
}
```

### `EarleyTableParseResult`

```swift
public struct EarleyTableParseResult {
    public let accepted:    Bool
    public let bsrSet:      Set<BSR<NodeLabel>>
    public let earleySets:  [Set<EarleyPair>]
    public let sppfGraph:   SPPFGraph<NodeLabel>?   // non-nil after EarleyTableParser.parse(tokens:)
    public var hasAmbiguity: Bool
}
```

### Low-level free functions

```swift
// Table construction
func buildEarleyNFA(grammar:)        -> EarleyNFA
func buildRecogniserTable(nfa:grammar:) -> RecogniserTable
func buildSLParseTable(nfa:grammar:) -> SLParseTable
func buildELParseTable(nfa:grammar:) -> ELParseTable   // NEW

// Parsing
func recET(table:input:)             -> Bool
func simpleET(table:input:)          -> EarleyTableParseResult
func parseET(table:input:)           -> EarleyTableParseResult   // NEW

// SPPF construction
func buildSPPF(from:grammar:tokens:) -> SPPFGraph<NodeLabel>

// Debug / test
func extractDerivation(from:grammar:tokens:) -> String?
```

---

## Bugs Fixed

The following bugs were corrected in this revision:

**1. `bsrSetIsAmbiguous` false positives** — The heuristic counted every repeated `(lhs, left, right)` triple, including prefix/intermediate BSR elements that legitimately repeat in every multi-symbol production. Fixed: only complete elements (`position == symbols.count`) with *differing pivots* signal genuine ambiguity.

**2. SPPF left-child for multi-symbol completed productions** — Completed productions with more than one symbol were silently dropping their left child. Fixed: any completed label with `symbols.count > 1` generates an intermediate SPPF node spanning `[leftExtent…pivot]`, exactly as partial labels do.

**3. Intermediate node dot position** — The label on intermediate nodes was written with `label.position − 1`, which is wrong for completed labels (where `position == symbols.count`). Fixed: uses `alpha.count − 1` where `alpha = symbols.prefix(position)`, correct for both completed and partial shapes.

**4. `reconstructChildren` for multi-symbol productions** — Previously returned a bare extent string `"[i…j via k]"` instead of recursing into the BSR set. Replaced with a proper recursive binary descent that handles every production shape.

**5. `EarleyTableParser.init` table selection** — Building only the SL table when `useExtendedLookahead == false` meant the EL table was unavailable after construction. Fixed: both tables are always built at `init` time (they are cheap relative to parsing); the algorithm is selected at call time inside `parse(tokens:)`.

**6. `EarleyTableParser.parse(tokens:)` unimplemented** — The method existed but had an empty body. Implemented: dispatches to `simpleET` or `parseET`, builds the SPPF, wraps in `EarleyTableParseResult`.

**7. `hasAmbiguity` false positives** — Was testing `getChildren(of:).count > 1` on every node. Packed nodes always have two children (left + right), so this was always `true`. Fixed: mirrors `Parser.GeneralizedParser.ParseResult.hasAmbiguity`: only `.symbol` and `.intermediate` nodes with more than one *packed* child signal ambiguity.

**8. `tokenizeAndParse` return type** — Was returning `ParseResult` (the generic Parser-module type), which has no `earleySets` field and mismatches callers that need Earley-specific data. Fixed to return `EarleyTableParseResult`.

---

## New Features

- **Extended-lookahead parser `parseET()`** — the `parseET()` function and the `ELParseTable` / `ELStateInfo` / `ELTableEntry` types. Toggle with `parser.useExtendedLookahead = true`. Uses `SELECT(p)` and `rLHS(p)` per state instead of the FOLLOW-based `A_{p,x}`.

- **`EarleyTableParser` public facade** — `EarleyTableParser` now fully conforms to both `DeterministicParser` and `GeneralizedParser` from the [hakkabon/Parser](https://github.com/hakkabon/Parser) module. `syntaxTree(for:)` and `allSyntaxTrees(for:)` delegate to `SPPFGraph.buildParseTree` / `buildAllParseTrees` (Parser module `TreeBuilder` extension) so tree construction is shared across parser implementations.

- **`parse(tokens:)`** — direct pre-tokenised API that bypasses the whitespace tokeniser, useful when the caller drives its own lexer.

- **`ParseResult<NodeLabel>`** — `GeneralizedParser.parse(_:)` now returns the shared `ParseResult<NodeLabel>` type (not the Earley-specific `EarleyTableParseResult`), which makes the facade interchangeable with other Parser-module conformers.

---

## Test Coverage

Nine suites, ~55 test cases (Swift Testing):

| Suite | What it covers |
|---|---|
| `EarleyParserTests` (existing) | NFA, `recET`, `simpleET`, SPPF, BSR, derivation extraction, edge cases |
| `PerformanceBenchmarks` (existing) | Recognition and parse speed |
| `AdditionalTests` (existing) | Core detection, Graphviz export, extendable nodes |
| `ELParserTests` *(new)* | `parseET` acceptance, BSR quality, ambiguity, EL table structure, three-way consistency |
| `EarleyTableParserFacadeTests` *(new)* | `recognizes`, `syntaxTree`, `parse`, `allSyntaxTrees`, SL/EL agreement, `parse(tokens:)` |

Run with:

```bash
swift test
```

---

## Dependencies

| Package | Role |
|---|---|
| [hakkabon/Grammar](https://github.com/hakkabon/Grammar) | `Grammar`, `Production`, `NonTerminal`, `Terminal`, `Symbol` |
| [hakkabon/Parser](https://github.com/hakkabon/Parser) | `BSR`, `SPPFGraph`, `SPPFNode`, `ParseResult`, `DeterministicParser`, `GeneralizedParser`, `TreeBuilder` |
| [hakkabon/GrammarTokenizer](https://github.com/hakkabon/GrammarTokenizer) | `TokenizerStream` used in `ParserTokenizer.swift` |

---

## References

- Scott, E. & Johnstone, A. (2026). *Earley Table Traversing Parsers*. Science of Computer Programming **247**, 103335. <https://doi.org/10.1016/j.scico.2025.103335>
- Earley, J. (1970). An efficient context-free parsing algorithm. *Communications of the ACM* **13**(2), 94–102.
- Scott, E. & Johnstone, A. (2013). BSR parsing. *Electronic Notes in Theoretical Computer Science* **253**, 17–51.
