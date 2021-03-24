// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import TSCUtility

private final class ContextKey {}

/// Support storing and retrieving file tree import options from a context
public extension Context {
    static func with(_ options: LLBCASFileTree.ImportOptions) -> Context {
        return Context(dictionaryLiteral: (ObjectIdentifier(LLBCASFileTree.ImportOptions.self), options as Any))
    }

    var fileTreeImportOptions: LLBCASFileTree.ImportOptions? {
        get {
            guard let options = self[ObjectIdentifier(LLBCASFileTree.ImportOptions.self)] as? LLBCASFileTree.ImportOptions else {
                return nil
            }

            return options
        }
        set {
            self[ObjectIdentifier(LLBCASFileTree.ImportOptions.self)] = newValue
        }
    }
}

/// Support storing and retrieving file tree export storage batcher from a context
public extension Context {
    private static let fileTreeExportStorageBatcherKey = ContextKey()

    var fileTreeExportStorageBatcher: LLBBatchingFutureOperationQueue? {
        get {
            guard let options = self[ObjectIdentifier(Self.fileTreeExportStorageBatcherKey)] as? LLBBatchingFutureOperationQueue else {
                return nil
            }

            return options
        }
        set {
            self[ObjectIdentifier(Self.fileTreeExportStorageBatcherKey)] = newValue
        }
    }
}
