//
//  GeneralizedParser.swift
//  Eerley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

#if false
/// The outcome of a parse attempt.
public struct ParseResult {
    public let isSuccessful: Bool
    public let bsr: Set<BinarySubtreeRepresentation>
    public let sppfGraph: SPPFGraph?

    /// Returns `true` if any non-terminal or intermediate SPPF node has more than one
    /// packed-node child, indicating that the grammar is locally ambiguous on this input.
    ///
    /// A packed node having two children is a normal binary split, not an ambiguity.
    /// Only `.symbol` and `.intermediate` nodes with multiple children signal ambiguity.
    public var hasAmbiguity: Bool {
        guard let graph = sppfGraph else { return false }
        return graph.getAllNodes().contains { node in
            switch node {
            case .symbol, .intermediate:
                return graph.getChildren(of: node).count > 1
            default:
                return false
            }
        }
    }
}
#endif

/// The result of an  simpleET()  run.
public struct ParseResult {
    /// True if and only if the input is in the grammar's language.
    public let accepted: Bool
    /// The BSR set Υ containing all binarised derivation subtrees.
    public let bsrSet: Set<BSRElement>
    /// The Earley sets 𝔼₀ … 𝔼_n.
    public let earleySets: [Set<EarleyPair>]
    /// SPPF graph (constructed on demand by calling buildSPPF()).
    public let sppfGraph: SPPFGraph?

    /// True if the BSR set witnesses more than one complete derivation tree
    /// for the recognised input, i.e. the grammar is ambiguous for this input.
    public var hasAmbiguity: Bool {
        guard let graph = sppfGraph else {
            // Use the SPPF graph when available; fall back to BSR heuristic.
            return bsrSetIsAmbiguous(bsrSet)
        }
        return graph.getAllNodes().contains { node in
            graph.getChildren(of: node).count > 1
        }
    }
}


/// A parser that recognises general (including ambiguous) context-free grammars and can
/// produce every derivation of an input string as a structured parse forest.
public protocol GeneralizedParser {

    /// Run the recogniser/parser on `string` and return the raw `ParseResult`.
    ///
    /// The result exposes the BSR set and the SPPF graph from which individual syntax
    /// trees can be extracted.  Use `allSyntaxTrees(for:)` if you want ready-made trees.
    ///
    /// - Parameter string: Input string to parse.
    /// - Returns: A `ParseResult` describing success, the BSR set, and the SPPF graph.
    /// - Throws: A `SyntaxError` if the string is not in the recognised language.
    func parse(_ string: String) throws -> ParseResult

    /// Returns **all** parse trees for `string`.
    ///
    /// For unambiguous grammars this returns exactly one tree.  For ambiguous grammars it
    /// returns one tree per distinct derivation.  Duplicates are removed before returning.
    ///
    /// - Parameter string: Input string to parse.
    /// - Returns: All syntax trees explaining how `string` was derived from the grammar.
    /// - Throws: A `SyntaxError` if the string is not in the recognised language.
    func allSyntaxTrees(for string: String) throws -> [ParseTree]
}
