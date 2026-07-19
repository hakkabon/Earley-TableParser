//
//  GeneralizedParser.swift
//  Earley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar
import Parser

/// The result of a `simpleET()` run.
///
/// This is intentionally distinct from the shared `Parser` module's generic
/// `ParseResult<Label>` — the table-traversing algorithm additionally
/// exposes the raw Earley sets 𝔼₀ … 𝔼_n, which the shared type has no field
/// for. Naming it differently from `Parser.ParseResult` also avoids an
/// unqualified-name collision now that this file `import`s `Parser`.
public struct EarleyTableParseResult {
    /// True if and only if the input is in the grammar's language.
    public let accepted: Bool
    /// The BSR set Υ containing all binarised derivation subtrees.
    public let bsrSet: Set<BSR<NodeLabel>>
    /// The Earley sets 𝔼₀ … 𝔼_n.
    public let earleySets: [Set<EarleyPair>]
    /// SPPF graph (constructed on demand by calling buildSPPF()).
    public let sppfGraph: SPPFGraph<NodeLabel>?

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
