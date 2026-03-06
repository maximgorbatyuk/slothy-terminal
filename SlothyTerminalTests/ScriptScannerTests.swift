import Foundation
import Testing

@testable import SlothyTerminalLib

@Suite("ScriptScanner")
struct ScriptScannerTests {
  private let scanner = ScriptScanner.shared

  private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("ScriptScannerTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func createFile(at dir: URL, name: String, content: String = "") throws {
    let fileURL = dir.appendingPathComponent(name)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
  }

  private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
  }

  // MARK: - Detection

  @Test("Detects .py files at project root")
  func detectsPythonFiles() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "deploy.py", content: "print('hello')\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.count == 1)
    #expect(results[0].name == "deploy.py")
    #expect(results[0].kind == .python)
  }

  @Test("Detects .sh files at project root")
  func detectsShellFiles() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "build.sh", content: "#!/bin/sh\necho hello\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.count == 1)
    #expect(results[0].name == "build.sh")
    #expect(results[0].kind == .shell)
  }

  @Test("Detects both .py and .sh files")
  func detectsBothKinds() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "run.py", content: "pass\n")
    try createFile(at: dir, name: "setup.sh", content: "echo ok\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.count == 2)
    let kinds = Set(results.map(\.kind))
    #expect(kinds == [.python, .shell])
  }

  @Test("Ignores unrelated file types")
  func ignoresUnrelatedFiles() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "readme.md", content: "# Readme\n")
    try createFile(at: dir, name: "config.json", content: "{}\n")
    try createFile(at: dir, name: "main.swift", content: "import Foundation\n")
    try createFile(at: dir, name: "Makefile", content: "all:\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.isEmpty)
  }

  // MARK: - Scan depth

  @Test("Scans scripts/ folder recursively")
  func scansScriptsRecursively() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let scriptsDir = dir.appendingPathComponent("scripts")
    let nestedDir = scriptsDir.appendingPathComponent("utils")
    try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

    try createFile(at: scriptsDir, name: "top.py", content: "pass\n")
    try createFile(at: nestedDir, name: "nested.sh", content: "echo\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.count == 2)
    let names = Set(results.map(\.name))
    #expect(names == ["top.py", "nested.sh"])
  }

  @Test("Does not scan non-scripts subdirectories recursively")
  func shallowRootScan() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    let subDir = dir.appendingPathComponent("src")
    try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

    try createFile(at: dir, name: "root.py", content: "pass\n")
    try createFile(at: subDir, name: "nested.py", content: "pass\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.count == 1)
    #expect(results[0].name == "root.py")
  }

  // MARK: - Sort order

  @Test("Results are sorted by name case-insensitively")
  func sortOrder() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "Zebra.py", content: "pass\n")
    try createFile(at: dir, name: "alpha.sh", content: "echo\n")
    try createFile(at: dir, name: "Beta.py", content: "pass\n")

    let results = scanner.scanSync(directory: dir)

    #expect(results.map(\.name) == ["alpha.sh", "Beta.py", "Zebra.py"])
  }

  // MARK: - Line counting

  @Test("Counts lines correctly")
  func lineCount() throws {
    let dir = try makeTempDir()
    defer { cleanup(dir) }

    try createFile(at: dir, name: "three.py", content: "a\nb\nc\n")
    try createFile(at: dir, name: "two.sh", content: "a\nb")

    let results = scanner.scanSync(directory: dir)

    let pyItem = results.first { $0.name == "three.py" }
    let shItem = results.first { $0.name == "two.sh" }

    #expect(pyItem?.lineCount == 3)
    #expect(shItem?.lineCount == 2)
  }
}

@Suite("ScriptScanner.relativePath")
struct ScriptRelativePathTests {
  @Test("Same directory returns filename only")
  func sameDirectory() {
    let base = URL(fileURLWithPath: "/tmp/project")
    let target = URL(fileURLWithPath: "/tmp/project/deploy.py")

    let result = ScriptScanner.relativePath(from: base, to: target)

    #expect(result == "deploy.py")
  }

  @Test("Nested script returns relative sub-path")
  func nestedScript() {
    let base = URL(fileURLWithPath: "/tmp/project")
    let target = URL(fileURLWithPath: "/tmp/project/scripts/utils/helper.sh")

    let result = ScriptScanner.relativePath(from: base, to: target)

    #expect(result == "scripts/utils/helper.sh")
  }

  @Test("Sibling directory uses parent traversal")
  func siblingDirectory() {
    let base = URL(fileURLWithPath: "/tmp/project/src")
    let target = URL(fileURLWithPath: "/tmp/project/scripts/build.sh")

    let result = ScriptScanner.relativePath(from: base, to: target)

    #expect(result == "../scripts/build.sh")
  }

  @Test("Completely different paths")
  func differentPaths() {
    let base = URL(fileURLWithPath: "/Users/dev/project")
    let target = URL(fileURLWithPath: "/opt/scripts/run.py")

    let result = ScriptScanner.relativePath(from: base, to: target)

    #expect(result == "../../../opt/scripts/run.py")
  }

  @Test("Scripts subfolder relative to project root")
  func scriptsSubfolder() {
    let base = URL(fileURLWithPath: "/Users/dev/myproject")
    let target = URL(fileURLWithPath: "/Users/dev/myproject/scripts/deploy.py")

    let result = ScriptScanner.relativePath(from: base, to: target)

    #expect(result == "scripts/deploy.py")
  }
}

@Suite("ScriptKind")
struct ScriptKindTests {
  @Test("Python execution command uses python3")
  func pythonExecutionCommand() {
    let cmd = ScriptKind.python.executionCommand(escapedPath: "'/tmp/test.py'")
    #expect(cmd == "python3 '/tmp/test.py'")
  }

  @Test("Shell execution command uses /bin/sh")
  func shellExecutionCommand() {
    let cmd = ScriptKind.shell.executionCommand(escapedPath: "'/tmp/test.sh'")
    #expect(cmd == "/bin/sh '/tmp/test.sh'")
  }

  @Test("Extension mapping works for supported types")
  func extensionMapping() {
    #expect(ScriptKind.from(extension: "py") == .python)
    #expect(ScriptKind.from(extension: "sh") == .shell)
    #expect(ScriptKind.from(extension: "rb") == nil)
    #expect(ScriptKind.from(extension: "js") == nil)
    #expect(ScriptKind.from(extension: "") == nil)
  }
}
