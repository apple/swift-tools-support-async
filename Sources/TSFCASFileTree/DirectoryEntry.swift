// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import Foundation

extension LLBDirectoryEntry {
    public init(name: String, type: LLBFileType, size: Int, posixDetails: LLBPosixFileDetails? = nil) {
        self.init(name: name, type: type, size: UInt64(clamping: size), posixDetails: posixDetails)
    }

    public init(name: String, type: LLBFileType, size: UInt64, posixDetails: LLBPosixFileDetails? = nil) {
        self.name = name
        self.type = type
        self.size = size
        if let pd = posixDetails, pd != LLBPosixFileDetails() {
            self.posixDetails = pd
        }
    }
}

extension LLBFileType {
    public var expectedPosixMode: mode_t {
        switch self {
        case .plainFile:
            return 0o644
        case .executable, .directory, .symlink:
            return 0o755
        case .UNRECOGNIZED:
            return 0
        }
    }
}

