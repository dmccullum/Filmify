import Foundation
import Testing
@testable import GranularCore

@Test func batchCountsPositionAndProgress() {
    var batch = ProcessingBatch(total: 3)
    #expect(batch.position == 1)
    #expect(batch.fractionComplete == 0)

    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/a.jpg"))
    batch.recordFailure()
    #expect(batch.position == 3)
    #expect(batch.completed == 2)
    #expect(batch.isFinished == false)

    batch.add(2)
    #expect(batch.total == 5)
    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/b.jpg"))
    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/c.jpg"))
    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/d.jpg"))
    #expect(batch.isFinished)
    #expect(batch.position == 5)
    #expect(batch.fractionComplete == 1)
    #expect(batch.outputs.map(\.lastPathComponent) == ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
}

@Test func batchSummaryReadsNaturally() {
    var batch = ProcessingBatch(total: 13)
    for index in 0..<12 {
        batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/\(index).jpg"))
    }
    batch.recordFailure()
    #expect(batch.summary(recipeName: "Portra 400") == "12 images processed with Portra 400 · 1 failed")

    var single = ProcessingBatch(total: 1)
    single.recordSuccess(output: URL(fileURLWithPath: "/tmp/one.jpg"))
    #expect(single.summary(recipeName: nil) == "1 image processed")

    var failures = ProcessingBatch(total: 2)
    failures.recordFailure()
    failures.recordFailure()
    #expect(failures.summary(recipeName: "Classic 35") == "2 images couldn’t be processed")
}

@Test func cancelledBatchSummaryCountsWhatWasSkipped() {
    var batch = ProcessingBatch(total: 10)
    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/a.jpg"))
    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/b.jpg"))
    batch.recordSuccess(output: URL(fileURLWithPath: "/tmp/c.jpg"))
    batch.isCancelled = true
    #expect(batch.summary(recipeName: "Soft 16") == "3 images processed with Soft 16 · 7 cancelled")
}

@Test func recentFoldersMoveToFrontWithoutDuplicates() {
    let a = URL(fileURLWithPath: "/Users/me/A", isDirectory: true)
    let b = URL(fileURLWithPath: "/Users/me/B", isDirectory: true)
    let c = URL(fileURLWithPath: "/Users/me/C", isDirectory: true)

    var folders = RecentFolders.adding(a, to: [])
    folders = RecentFolders.adding(b, to: folders)
    folders = RecentFolders.adding(URL(fileURLWithPath: "/Users/me/A/"), to: folders)
    #expect(folders.map(\.lastPathComponent) == ["A", "B"])

    folders = RecentFolders.adding(c, to: folders, limit: 2)
    #expect(folders.map(\.lastPathComponent) == ["C", "A"])
}
