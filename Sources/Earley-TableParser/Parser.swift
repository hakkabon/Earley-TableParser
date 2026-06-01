//
//  Parser.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

/// A parser that can parse ambiguous grammars and retrieve every possible syntax tree
public protocol GeneralizedParser {
    /// Generates all syntax trees explaining how a word can be derived from a grammar.
    ///
    /// This function should only be used for ambiguous grammars and if it is necessary to
    /// retrieve all parse trees, as it comes with an additional cost in runtime.
    ///
    /// For unambiguous grammars, this function should return the same results as `syntaxTree(for:)`.
    ///
    /// - Parameter string: Input word, for which all parse trees should be generated
    /// - Returns: All syntax trees which explain how the input was derived from the recognized grammar
    /// - Throws: A syntax error if the word is not in the language recognized by the parser
    func parse(_ string: String) throws -> EarleyParseResult
}

/// Deprecated alias kept for source compatibility.
@available(*, deprecated, renamed: "GeneralizedParser")
public typealias GereralizedParser = GeneralizedParser

