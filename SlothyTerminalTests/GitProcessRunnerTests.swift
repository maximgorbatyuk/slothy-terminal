import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("GitProcessRunner")
struct GitProcessRunnerTests {
  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("GitProcessRunnerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func makeHelperProcess(in directory: URL) throws -> URL {
    let helperURL = directory.appendingPathComponent("process-helper.sh")
    let script = """
    #!/bin/sh
    mode="$1"

    case "$mode" in
      trim)
        printf '  hello world\\n'
        ;;
      mixed)
        printf 'alpha\\n'
        printf 'beta\\n' >&2
        ;;
      sleep)
        sleep "$2"
        ;;
      *)
        printf 'unknown mode: %s\\n' "$mode" >&2
        exit 1
        ;;
    esac
    """

    try script.write(to: helperURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
    return helperURL
  }

  private func cleanup(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
  }

  @Test("Trims stdout from successful helper process")
  func trimsSuccessfulOutput() async throws {
    let directory = try makeTempDir()
    defer { cleanup(directory) }

    let helper = try makeHelperProcess(in: directory)

    let result = await GitProcessRunner.runProcessResult(
      executableURL: helper,
      arguments: ["trim"],
      in: nil,
      environment: nil,
      timeout: 1
    )

    #expect(result.isSuccess)
    #expect(result.didTimeOut == false)
    #expect(result.wasCancelled == false)
    #expect(result.stdout == "hello world")
    #expect(result.stderr.isEmpty)
  }

  @Test("Captures both stdout and stderr from helper process")
  func capturesMixedOutput() async throws {
    let directory = try makeTempDir()
    defer { cleanup(directory) }

    let helper = try makeHelperProcess(in: directory)

    let result = await GitProcessRunner.runProcessResult(
      executableURL: helper,
      arguments: ["mixed"],
      in: nil,
      environment: nil,
      timeout: 1
    )

    #expect(result.isSuccess)
    #expect(result.didTimeOut == false)
    #expect(result.wasCancelled == false)
    #expect(result.stdout == "alpha")
    #expect(result.stderr == "beta")
  }

  @Test("Times out long-running helper process")
  func timesOutLongRunningProcess() async throws {
    let directory = try makeTempDir()
    defer { cleanup(directory) }

    let helper = try makeHelperProcess(in: directory)
    let start = Date()

    let result = await GitProcessRunner.runProcessResult(
      executableURL: helper,
      arguments: ["sleep", "5"],
      in: nil,
      environment: nil,
      timeout: 0.2
    )

    let elapsed = Date().timeIntervalSince(start)

    #expect(result.isSuccess == false)
    #expect(result.didTimeOut)
    #expect(result.wasCancelled == false)
    #expect(result.stderr.contains("timed out"))
    #expect(elapsed < 2)
  }

  @Test("Cancelling helper process returns promptly")
  func cancelingLongRunningProcess() async throws {
    let directory = try makeTempDir()
    defer { cleanup(directory) }

    let helper = try makeHelperProcess(in: directory)
    let start = Date()

    let task = Task {
      await GitProcessRunner.runProcessResult(
        executableURL: helper,
        arguments: ["sleep", "5"],
        in: nil,
        environment: nil,
        timeout: 5
      )
    }

    try? await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()

    let result = await task.value
    let elapsed = Date().timeIntervalSince(start)

    #expect(result.isSuccess == false)
    #expect(result.didTimeOut == false)
    #expect(result.wasCancelled)
    #expect(result.stderr.contains("cancelled"))
    #expect(elapsed < 2)
  }
}
