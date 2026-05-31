//
//  Parser.swift
//  Grammar
//
//  Created by Ulf Akerstedt-Inoue on 2023/08/11.
//  Copyright © 2023 hakkabon software. All rights reserved.
//

import Foundation
import Grammar

#if false

/// The outcome of a parse attempt.
public enum ParseResult {
    /// Parse succeeded; the BSR set and SPPF graph are available.
    case success(bsr: BSRSet, sppf: SPPFGraph)
    /// Parse failed; `position` is the furthest token that was consumed.
    case failure(position: Int, message: String)

    public var hasAmbiguity: Bool {
        switch self {
        case let .success(s,graph):
            return graph.getAllNodes().contains { node in
                graph.getChildren(of: node).count > 1
            }
        default: return false
        }
    }
}

#endif

public struct ParseResult {
    public let isSuccessful: Bool
    public let bsr: Set<BinarySubtreeRepresentation>
    public let sppfGraph: SPPFGraph?
    
    public var hasAmbiguity: Bool {
        guard let graph = sppfGraph else { return false }
        
        // Check if any node has multiple children (multiple derivations)
        return graph.getAllNodes().contains { node in
            graph.getChildren(of: node).count > 1
        }
    }
}


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
    func parse(_ string: String) throws -> ParseResult
}

/// Deprecated alias kept for source compatibility.
@available(*, deprecated, renamed: "GeneralizedParser")
public typealias GereralizedParser = GeneralizedParser

