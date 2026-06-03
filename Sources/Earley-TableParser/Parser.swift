//
//  Parser.swift
//  Earley-TableParser
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// A parser that can parse potentially ambiguous grammars and retrieve every
/// possible parse (syntax) tree.
public protocol GeneralizedParser {
    /// Parse the given string and return a parse result.
    ///
    /// - Parameter string: The input string to parse.
    /// - Returns: An `EarleyParseResult` describing whether the parse succeeded
    ///   and carrying the BSR set / SPPF graph representing all derivations.
    /// - Throws: A `SyntaxError` if the input is not in the grammar's language.
    func parse(_ string: String) throws -> EarleyParseResult
}

/// Source-compatibility alias (deprecated).
@available(*, deprecated, renamed: "GeneralizedParser")
public typealias GereralizedParser = GeneralizedParser
