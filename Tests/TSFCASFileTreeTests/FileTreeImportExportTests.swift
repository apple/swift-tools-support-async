// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors


import Dispatch
import XCTest

import TSCBasic
import TSCUtility

import TSFCASFileTree


class ImportExportTests: XCTestCase {

    var testOptions: LLBCASFileTree.ImportOptions {
        var options = LLBCASFileTree.ImportOptions()
        // These settings are important for keeping tests small.
        options.fileChunkSize = 4096
        options.minMmapSize = 4096
        return options
    }

    func testBasicFilesystemExport() throws{
        let group = LLBMakeDefaultDispatchGroup()
        let ctx = Context()

        try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { dir in
            let tmpdir = dir.appending(component: "first")

            // Create sample file system content.
            let fs = TSCBasic.localFileSystem
            try fs.createDirectory(tmpdir)

            let db = LLBInMemoryCASDatabase(group: group)

            let inTree: LLBDeclFileTree = .dir(["a.txt": .file("hi"),
                                            "dir": .dir(["b.txt": .file("hello"),
                                                         "c.txt": .file("world")
                                            ])
            ])
            let id = try LLBCASFSClient(db).store(inTree, ctx).wait().asDirectoryEntry(filename: "").id

            // Get the object.
            let tree: LLBCASFileTree
            do {
                let casObject = try db.get(id, ctx).wait()
                tree = try LLBCASFileTree(id: id, object: casObject!)
            } catch {
                XCTFail("Unexpected CASTree download error: \(errno)")
                throw error
            }

            // Check the result.
            XCTAssertEqual(tree.files, [
                LLBDirectoryEntry(name: "a.txt", type: .plainFile, size: 2),
                LLBDirectoryEntry(name: "dir", type: .directory, size: 10)])

            // Export the results.
            let tmpdir2 = dir.appending(component: "second")
            try fs.createDirectory(tmpdir2)
            try LLBCASFileTree.export(
                id,
                from: db,
                to: tmpdir2,
                stats: LLBCASFileTree.ExportProgressStatsInt64(),
                ctx
            ).wait()

            // Check the file was exported.
            XCTAssertEqual(try fs.readFileContents(tmpdir2.appending(component: "a.txt")), "hi")
        }

        XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    func testBasicFilesystemImport() throws{
        let group = LLBMakeDefaultDispatchGroup()
        let ctx = Context()

        for (wireFormat, expectedUploadSize) in [(LLBCASFileTree.WireFormat.binary, 68), (.compressed, 68)] {
            try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { dir in
                let tmpdir = dir.appending(component: "first")

                // Create sample file system content.
                let fs = TSCBasic.localFileSystem
                try fs.createDirectory(tmpdir)
                try fs.writeFileContents(tmpdir.appending(component: "a.txt"), bytes: "hi")
                let subpath = tmpdir.appending(component: "dir")
                try fs.createDirectory(subpath, recursive: true)
                try fs.writeFileContents(subpath.appending(component: "b.txt"), bytes: "hello")
                try fs.writeFileContents(subpath.appending(component: "c.txt"), bytes: "world")

                let db = LLBInMemoryCASDatabase(group: group)
                let stats = LLBCASFileTree.ImportProgressStats()

                let id = try LLBCASFileTree.import(path: tmpdir, to: db, options: testOptions.with(wireFormat: wireFormat), stats: stats, ctx).wait()
                XCTAssertEqual(stats.uploadedBytes - stats.uploadedMetadataBytes, 12)
                XCTAssertEqual(stats.uploadedBytes, expectedUploadSize)
                XCTAssertEqual(stats.importedBytes, expectedUploadSize)
                XCTAssertEqual(stats.toImportBytes, expectedUploadSize)
                XCTAssertEqual(stats.phase, .ImportSucceeded)

                // Get the object.
                let tree: LLBCASFileTree
                do {
                    let casObject = try db.get(id, ctx).wait()
                    tree = try LLBCASFileTree(id: id, object: casObject!)
                } catch {
                    XCTFail("Unexpected CASTree download error: \(errno)")
                    throw error
                }

                // Check the result.
                XCTAssertEqual(tree.files, [
                    LLBDirectoryEntry(name: "a.txt", type: .plainFile, size: 2),
                    LLBDirectoryEntry(name: "dir", type: .directory, size: 10)])

                // Export the results.
                let tmpdir2 = dir.appending(component: "second")
                try fs.createDirectory(tmpdir2)
                try LLBCASFileTree.export(
                    id,
                    from: db,
                    to: tmpdir2,
                    stats: LLBCASFileTree.ExportProgressStatsInt64(),
                    ctx
                ).wait()

                // Check the file was exported.
                XCTAssertEqual(try fs.readFileContents(tmpdir2.appending(component: "a.txt")), "hi")
            }
        }

        XCTAssertNoThrow(try group.syncShutdownGracefully())
    }

    func testImportMissingDirectory() throws {
        let group = LLBMakeDefaultDispatchGroup()
        let ctx = Context()

        try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { dir in
            let somedir = dir.appending(component: "some")

            // Create sample file system content.
            let fs = TSCBasic.localFileSystem
            try fs.createDirectory(somedir)

            let nonexistDir = somedir.appending(component: "nonexist")
            let db = LLBInMemoryCASDatabase(group: group)
            XCTAssertThrowsError(try LLBCASFileTree.import(path: nonexistDir, to: db, options: testOptions, ctx).wait()) { error in
                XCTAssertEqual(error as? FileSystemError, FileSystemError(.noEntry, nonexistDir))
            }
        }
    }

    func testUnicodeImport() throws {
        let group = LLBMakeDefaultDispatchGroup()
        let ctx = Context()

        try withTemporaryDirectory(prefix: #function, removeTreeOnDeinit: true) { dir in
            let target = "你好 你好"
            let ret = symlink(target, dir.appending(component: "コカコーラ").pathString)
            XCTAssertEqual(ret, 0)

            let db = LLBInMemoryCASDatabase(group: group)
            let stats = LLBCASFileTree.ImportProgressStats()

            let id = try LLBCASFileTree.import(
                path: dir, to: db, options: testOptions, stats: stats, ctx
            ).wait()

            // Get the object.
            let tree: LLBCASFileTree
            do {
                let casObject = try db.get(id, ctx).wait()
                tree = try LLBCASFileTree(id: id, object: casObject!)
            } catch {
                XCTFail("Unexpected CASTree download error: \(errno)")
                throw error
            }

            // Check the result.
            XCTAssertEqual(
                tree.files,
                [
                    LLBDirectoryEntry(name: "コカコーラ", type: .symlink, size: target.utf8.count),
                ])
        }

        XCTAssertNoThrow(try group.syncShutdownGracefully())
    }


}
