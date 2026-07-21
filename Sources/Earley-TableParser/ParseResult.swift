//
//  ParseResult.swift
//  Earley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser

/// The result of a `simpleET()` or `parseET()` run.
///
/// Intentionally distinct from the shared `Parser` module's generic
/// `ParseResult<Label>`: this type additionally exposes the raw Earley
/// sets 𝔼₀ … 𝔼_n, which the shared type has no field for.
///
/// `EarleyTableParser.parse(_:)` wraps this in `ParseResult<NodeLabel>`
/// (the Parser-module type) when conforming to `GeneralizedParser`.
public struct EarleyTableParseResult {
    /// True iff the input is in the grammar's language.
    public let accepted: Bool
    /// The BSR set Υ containing all binarised derivation subtrees.
    public let bsrSet: Set<BSR<NodeLabel>>
    /// The Earley sets 𝔼₀ … 𝔼_n.
    public let earleySets: [Set<EarleyPair>]
    /// SPPF graph. Non-nil after `EarleyTableParser.parse(tokens:)` succeeds;
    /// nil when coming directly from the free `simpleET`/`parseET` functions.
    public let sppfGraph: SPPFGraph<NodeLabel>?

    /// True if the SPPF (or, as a fallback, the BSR heuristic) signals that
    /// the grammar is locally ambiguous for this input.
    ///
    /// BUG 7 fix: the previous check (`getChildren(of:).count > 1` on every
    /// node) was always true for packed nodes, which always have two children
    /// (a left and a right child).  Ambiguity is indicated by a .symbol or
    /// .intermediate node having *more than one packed child*.
    public var hasAmbiguity: Bool {
        if let graph = sppfGraph {
            return graph.getAllNodes().contains { node in
                switch node {
                case .symbol, .intermediate:
                    // Count only the packed-node children — those represent
                    // alternative derivations for this span.
                    let packedChildCount = graph.getChildren(of: node).filter {
                        if case .packed = $0 { return true }
                        return false
                    }.count
                    return packedChildCount > 1   // BUG 7 fix
                default:
                    return false
                }
            }
        }
        return bsrSetIsAmbiguous(bsrSet)
    }
}
