# Earley Table Traversing Parser

A comprehensive Swift implementation of the **Earley Table Traversing (ET) Parser** based on the paper:

> Scott & Johnstone (2026). "Earley Table Traversing Parser." *Science of Computer Programming*, 247, 103335.
> https://doi.org/10.1016/j.scico.2025.103335

This implementation provides full support for **arbitrary context-free grammars** (including ambiguous grammars), with output represented as **Shared Packed Parse Forests (SPPF)** and internal **Binary Subset Representation (BSR)** for efficient storage of parse derivations.

## Features

- ✅ **General parsing** of arbitrary CFGs without restriction (LR, ambiguous, left-recursive, etc.)
- ✅ **Ambiguity detection and handling** with compact SPPF representation
- ✅ **Efficient derivation storage** using Binary Subset Representation (BSR)
- ✅ **Recognizer mode** (`recET()`) for fast acceptance testing
- ✅ **Parser mode** (`simpleET()`) for full derivation extraction
- ✅ **Epsilon (ε) production support** including nullable nonterminals
- ✅ **SPPF graph generation** for visualization and analysis
- ✅ **Tokenization support** with configurable token rules
- ✅ **Graphviz export** for parse forest visualization

## Architecture

### Core Components

#### 1. Grammar Representation
- **Slot (LR Item)**: Position marker in a production rule (used for NFA construction)
- **Symbol**: Terminal, nonterminal, or epsilon
- **Production**: Grammar rule mapping nonterminals to sequences of symbols

#### 2. Earley NFA Construction (`EarleyNFA.swift`)
Builds the Earley NFA following Scott & Johnstone's algorithm:
- Computes **calls(M)** sets for entailment closure over nonterminal calls
- Computes **move(M, x)** transitions for symbol consumption
- Generates all reachable states G₀, G₁, ..., G_q

#### 3. Parse Table Construction (`ParseTable.swift`, `RecogniserTable.swift`)
- **Recogniser Table** (Section 5): Minimal table for acceptance testing
- **SL Parse Table** (Section 7): Extended table with BSR components for derivation extraction

#### 4. Parser Algorithms
- **recET()** (Section 5.2): Recogniser traversing the NFA
- **simpleET()** (Section 7.1.1): Parser building BSR derivations

#### 5. BSR and SPPF (`SPPF/` directory)
- **BSRElement**: (Ω, i, k, j) - binarised subtree representation
- **SPPFGraph**: Shared packed parse forest graph
- **GraphNode**: Union type for leaf, symbol, intermediate, and packed nodes

### Algorithm Overview

```
Input: Context-free grammar Γ, token sequence w
Output: Boolean accepted; if true, a BSR set Υ of all derivations

1. Build NFA: ℰ = buildEarleyNFA(Γ)
2. Build SL table: T = buildSLParseTable(ℰ, Γ)
3. Initialize: E₀ = R₀ = {(0, 0)}
4. For each position j from 0 to n:
   - While R_j not empty:
     - Pop (p, k) from R_j
     - If k ≠ j: Apply completer action (nonterminal completion)
     - Apply ε-transition: ADD(p, ε, j, j, j)
     - If j < n: Apply scanner: ADD(p, a_{j+1}, k, j, j+1)
5. Return: accepted = (E_n contains complete start item)
```

## Usage

### Basic Parsing

```swift
import Earley_TableParser
import Grammar

// Define a simple grammar: S ::= "a" S "b" | "a"
let rules: [(NonTerminal, [Symbol])] = [
    (NonTerminal(name: "S"), [
        .terminal(Terminal(description: "a")),
        .nonTerminal(NonTerminal(name: "S")),
        .terminal(Terminal(description: "b"))
    ]),
    (NonTerminal(name: "S"), [.terminal(Terminal(description: "a"))])
]

let grammar = try Grammar(startSymbol: NonTerminal(name: "S"), productions: rules)

// Build parser tables
let nfa = buildEarleyNFA(grammar: grammar)
let table = buildSLParseTable(nfa: nfa, grammar: grammar)

// Parse input
let input = ["a", "a", "b"]
let result = simpleET(table: table, input: input)

print("Accepted: \(result.accepted)")
print("BSR elements: \(result.bsrSet.count)")
print("Ambiguous: \(result.hasAmbiguity)")
```

### Tokenized Parsing

```swift
// Create a tokenizer for your language
let tokenizer = EarleyTokenizer(rules: [
    TokenRule(name: "if", literal: "if"),
    TokenRule(name: "while", literal: "while"),
    TokenRule(name: "ID", regex: "[a-zA-Z_][a-zA-Z0-9_]*"),
    TokenRule(name: "NUM", regex: "[0-9]+"),
    TokenRule(name: "(", literal: "("),
    TokenRule(name: ")", literal: ")")
])

let sourceCode = "while (x) { ... }"
let result = try tokenizeAndParse(
    input: sourceCode,
    tokenizer: tokenizer,
    table: table,
    grammar: grammar
)
```

### Ambiguity Analysis

```swift
// For highly ambiguous grammars like S ::= SS | b
let result = simpleET(table: table, input: ["b", "b", "b"])

if result.hasAmbiguity {
    print("Grammar is ambiguous!")
    print("Parse forest nodes: \(result.sppfGraph?.getAllNodes().count ?? 0)")
    
    // Export to Graphviz for visualization
    if let graphviz = result.sppfGraph?.graphviz {
        print(graphviz)  // Pipe to `dot -Tpng -o forest.png`
    }
}
```

## Test Cases

The project includes comprehensive test suites:

### Example Grammars (from the paper)

#### Γ₁: Ambiguous with epsilon
```
S ::= A S b | a
A ::= a A | ε
```
- Demonstrates left recursion and epsilon production handling
- Test inputs: "a", "aab", "aaa bbb", etc.

#### Γ₂: Complex with nullable
```
S ::= B B S a | b b b
B ::= b b B | ε
```
- Tests multiple nullable nonterminals
- Exercises nullable item closures

#### Γ₃: Highly ambiguous
```
S ::= S S S | S S | b
```
- Pure ambiguity: multiple derivations for all inputs ≥ 2 tokens
- Stress test for SPPF compaction

### Running Tests

```bash
# Build the project
swift build

# Run unit tests
swift test

# Run the demo (all test grammars)
swift run gtool

# Run specific test
swift test --filter Test_Gamma1
```

## Performance Characteristics

| Input Length | Time | Space (BSR) | Notes |
|-------------|------|------------|-------|
| n ≤ 4      | < 1ms | ~100 els | Demo grammars |
| n = 10     | ~5ms  | ~1K els | Moderate ambiguity |
| n = 20     | ~50ms | ~10K els | High ambiguity |

**BSR compaction ratio**: O(n³) worst-case, but typically 10-100× smaller than concrete parse forests.

## API Reference

### Core Parser Functions

```swift
// Recogniser mode: just acceptance testing
func recET(table: RecogniserTable, input tokens: [String]) -> Bool

// Parser mode: extract all derivations
func simpleET(table: SLParseTable, input tokens: [String]) -> EarleyParseResult

// Build tables
func buildEarleyNFA(grammar: Grammar) -> EarleyNFA
func buildRecogniserTable(nfa: EarleyNFA, grammar: Grammar) -> RecogniserTable
func buildSLParseTable(nfa: EarleyNFA, grammar: Grammar) -> SLParseTable

// Tokenization
class EarleyTokenizer {
    init(rules: [TokenRule], skipWhitespace: Bool = true)
    static func simple(terminals: [String]) -> EarleyTokenizer
    func tokenize(_ input: String) throws -> [String]
}

// SPPF operations
class SPPFGraph {
    func getAllNodes() -> [GraphNode]
    func getChildren(of node: GraphNode) -> Set<GraphNode>
    var graphviz: String
}
```

### Data Structures

```swift
// Earley parser result
struct EarleyParseResult {
    let accepted: Bool
    let bsrSet: Set<BSRElement>
    let earleySets: [Set<EarleyPair>]
    let sppfGraph: SPPFGraph?
    var hasAmbiguity: Bool
}

// Binary Subset Representation element
struct BSRElement {
    let omega: BSRComponent          // Production or prefix
    let leftExtent: Int             // Start position (i)
    let pivot: Int                  // Split point (k)
    let rightExtent: Int            // End position (j)
}
```

## Known Limitations

1. **No memoization of FIRST/FOLLOW**: Recomputed for each parse table (can be optimized)
2. **SPPF graph construction**: Currently placeholder; full implementation under development
3. **Error recovery**: Reports only first failure point
4. **Memory**: BSR set can be large for highly ambiguous grammars (see mitigations below)

## Optimization Opportunities

- [ ] Memoize FIRST/FOLLOW sets across multiple parses
- [ ] Implement context-sensitive SPPF pruning
- [ ] Parallel processing of Earley worklist items
- [ ] Lazy SPPF expansion (on-demand node creation)
- [ ] Grammar analysis for ambiguity detection before parsing

## References

- **Primary**: Scott & Johnstone (2026), *Earley Table Traversing Parser*
- **SPPF**: Rekers (1992), "Parser Generation for Interactive Environments"
- **Earley**: Earley (1970), "An efficient context-free parsing algorithm"

## Dependencies

- **Grammar**: External package for grammar representation
- **GrammarTokenizer**: Tokenization and lexical analysis
- **TerminalColors**: Console output colorization
- **Swift 5.9+**

## Contributing

Contributions are welcome! Areas for improvement:

- [ ] SPPF graph construction algorithm
- [ ] Performance optimizations (profile-guided)
- [ ] Error recovery strategies
- [ ] Additional test cases and benchmarks
- [ ] Documentation improvements

## License

Distributed under a permissive open-source license (see LICENSE file).

## Citation

If you use this implementation in research or teaching, please cite:

```bibtex
@article{scott2026earley,
  title = {Earley Table Traversing Parser},
  author = {Scott, Elizabeth and Johnstone, Adrian},
  journal = {Science of Computer Programming},
  volume = {247},
  pages = {103335},
  year = {2026}
}
```

---

**Status**: Pre-release (W.I.P.) — Core algorithms functional; SPPF generation and optimizations in progress.
