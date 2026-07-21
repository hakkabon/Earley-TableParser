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

/// Internal working result of a table traversal. Earley sets are retained for
/// algorithm tests and diagnostics, but are not part of the parser's public
/// result contract.
struct TableTraversalResult {
    /// True iff the input is in the grammar's language.
    let accepted: Bool
    /// The BSR set Υ containing all binarised derivation subtrees.
    let bsrSet: Set<BSR<NodeLabel>>
    /// The Earley sets 𝔼₀ … 𝔼_n.
    let earleySets: [Set<EarleyPair>]
    var hasAmbiguity: Bool {
        return bsrSetIsAmbiguous(bsrSet)
    }
}
