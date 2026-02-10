import ConsoleKit
import CoreImage
import Dispatch
import Foundation
import Darwin
import ImageIO

enum ExportHEICError: Error, CustomStringConvertible {
  var description: String {
    switch self {
    case .couldNotReadImage:
      return "Could not read image file"
    case .invalidInputDirectory(let path):
      return "Input directory is missing or not a directory: \(path)"
    case .couldNotEnumerateDirectory(let path):
      return "Could not enumerate input directory: \(path)"
    }
  }

  case couldNotReadImage
  case invalidInputDirectory(String)
  case couldNotEnumerateDirectory(String)
}

struct ExportHEICCommand: Command {
  public struct ExportHEICCommandSignature: CommandSignature {
    @Option(name: "input-file", help: "Path to input image file")
    var inputFile: String?

    @Option(
      name: "input-dir",
      help: "Root directory to scan for .avif files (recursively). Output is written next to inputs"
    )
    var inputDir: String?

    @Option(
      name: "quality",
      help: "Compression quality between 0.0-1.0 (default: 0.8). Cannot be used with --size-limit",
      allowedValues: Float(0)...Float(1))
    var quality: Float?

    @Option(
      name: "size-limit",
      help: "Limit the size in bytes of the resulting image file, instead of specifying a "
        + "quality directly. Cannot be used with --quality",
      allowedValues: Int64(1)...Int64.max)
    var sizeLimit: Int64?

    @Option(
      name: "min-quality",
      help: "Minimal allowed compression quality, between 0.0-1.0, if --size-limit is used. Default: 0.0",
      allowedValues: 0.0...1.0)
    var minQuality: Double?

    @Option(
      name: "max-quality",
      help: "Maximal allowed compression quality, between 0.0-1.0, if --size-limit is used. Default: 1.0",
      allowedValues: 0.0...1.0)
    var maxQuality: Double?

    @Option(
      name: "color-space",
      help: "Name of the output color space. Omit to use input image color space",
      allowedValues: [
        CGColorSpace.sRGB,
        CGColorSpace.displayP3,
        CGColorSpace.adobeRGB1998,
      ].map { ($0 as String).replacingOccurrences(of: "kCGColorSpace", with: "") })
    var colorSpaceName: String?

    @Option(
      name: "jobs",
      help: "Number of files to process in parallel when using --input-dir. Default: performance core count",
      allowedValues: 1...Int.max)
    var jobs: Int?

    @Argument(
      name: "output-file",
      help: "Path to where the output file will be placed (required with --input-file)"
    )
    var outputFile: String

    @Flag(name: "verbose")
    var verbose: Bool

    var inputFileURL: URL? {
      guard let inputFile = self.inputFile else {
        return nil
      }

      return URL(fileURLWithPath: inputFile)
    }

    var outputFileURL: URL {
      return URL(fileURLWithPath: outputFile)
    }

    var colorSpace: CGColorSpace? {
      guard let colorSpaceName = self.colorSpaceName else {
        return nil
      }

      return CGColorSpace(name: "kCGColorSpace\(colorSpaceName)" as CFString)
    }

    public init() {}
  }

  var help: String {
    return "Export input image file as HEIC, or batch convert .avif files in a directory"
  }

  func run(using context: CommandContext, signature: ExportHEICCommandSignature) throws {
    try signature.enhanceOptions()
    try signature.checkOptions()

    if let inputDir = signature.inputDir {
      try runBatch(using: context, signature: signature, inputDir: inputDir)
      return
    }

    guard let inputURL = signature.inputFileURL else {
      throw ExportHEICError.couldNotReadImage
    }
    let outputURL = signature.outputFileURL

    try convertFile(
      inputURL: inputURL,
      outputURL: outputURL,
      signature: signature,
      console: context.console)
  }

  private func runBatch(
    using context: CommandContext,
    signature: ExportHEICCommandSignature,
    inputDir: String
  ) throws {
    let rootURL = URL(fileURLWithPath: inputDir, isDirectory: true)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir),
      isDir.boolValue
    else {
      throw ExportHEICError.invalidInputDirectory(rootURL.path)
    }

    let inputFiles = try findAVIFFiles(in: rootURL)
    if signature.verbose {
      context.console.print("Found \(inputFiles.count) .avif file(s) under \(rootURL.path)")
    }
    if inputFiles.isEmpty {
      return
    }

    let jobs = max(1, signature.jobs ?? defaultJobCount())
    if jobs <= 1 {
      for inputURL in inputFiles {
        let outputURL = outputURLForInput(inputURL)
        try convertFile(
          inputURL: inputURL,
          outputURL: outputURL,
          signature: signature,
          console: context.console)
      }
      return
    }

    let semaphore = DispatchSemaphore(value: jobs)
    let group = DispatchGroup()
    let queue = DispatchQueue.global(qos: .userInitiated)
    let lock = NSLock()
    var firstError: Error?

    for inputURL in inputFiles {
      semaphore.wait()
      group.enter()
      queue.async {
        defer {
          semaphore.signal()
          group.leave()
        }
        do {
          let outputURL = outputURLForInput(inputURL)
          try convertFile(
            inputURL: inputURL,
            outputURL: outputURL,
            signature: signature,
            console: context.console)
        } catch {
          lock.lock()
          if firstError == nil {
            firstError = error
          }
          lock.unlock()
        }
      }
    }

    group.wait()
    if let error = firstError {
      throw error
    }
  }

  private func outputURLForInput(_ inputURL: URL) -> URL {
    return inputURL.deletingPathExtension().appendingPathExtension("heic")
  }

  private func findAVIFFiles(in rootURL: URL) throws -> [URL] {
    let fileManager = FileManager.default
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard
      let enumerator = fileManager.enumerator(
        at: rootURL,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles])
    else {
      throw ExportHEICError.couldNotEnumerateDirectory(rootURL.path)
    }

    var results: [URL] = []
    for case let fileURL as URL in enumerator {
      if fileURL.pathExtension.lowercased() == "avif" {
        results.append(fileURL)
      }
    }

    results.sort { $0.path < $1.path }
    return results
  }

  private func convertFile(
    inputURL: URL,
    outputURL: URL,
    signature: ExportHEICCommandSignature,
    console: Console
  ) throws {
    let inputImage = CIImage(contentsOf: inputURL)
    guard let inputImage = inputImage else {
      throw ExportHEICError.couldNotReadImage
    }

    let bitDepth = inputImage.properties["Depth"] as? Int ?? 8
    let colorSpace =
      signature.colorSpace ?? inputImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let shouldUseHEIF10 = bitDepth > 8
    let metadata = readMetadata(from: inputURL)

    if signature.verbose {
      console.print("Input URL: \(inputURL.path)")
      if let inputColorSpace = inputImage.colorSpace {
        console.print("Input Colorspace: \(inputColorSpace)")
      } else {
        console.print("Input Colorspace: <none>")
      }
      console.print("Input Bitdepth: \(bitDepth)")
      if metadata != nil {
        console.print("Input Metadata: <present>")
      } else {
        console.print("Input Metadata: <none>")
      }
    }

    try? FileManager.default.removeItem(at: outputURL)

    if let sizeLimit = signature.sizeLimit {
      try writeSizeLimitedHEIF(
        of: inputImage,
        to: outputURL,
        in: colorSpace,
        withSizeLimit: sizeLimit,
        withinRange: (signature.minQuality ?? 0)...(signature.maxQuality ?? 1),
        shouldUseHEIF10: shouldUseHEIF10,
        verbose: signature.verbose)
    } else {
      let quality = signature.quality ?? 0.8
      try writeHEIF(
        of: inputImage,
        to: outputURL,
        in: colorSpace,
        withQuality: quality,
        shouldUseHEIF10: shouldUseHEIF10,
        verbose: signature.verbose)
    }

    if let metadata = metadata {
      applyMetadata(metadata, to: outputURL, verbose: signature.verbose)
    }
  }

  private func readMetadata(from url: URL) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
  }

  private func applyMetadata(_ metadata: [String: Any], to url: URL, verbose: Bool) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      if verbose { consolePrint("Metadata: could not read output file") }
      return
    }
    guard let type = CGImageSourceGetType(source) else {
      if verbose { consolePrint("Metadata: unknown output image type") }
      return
    }

    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
    guard let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, type, 1, nil) else {
      if verbose { consolePrint("Metadata: could not create destination") }
      return
    }

    CGImageDestinationAddImageFromSource(dest, source, 0, metadata as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
      if verbose { consolePrint("Metadata: failed to finalize destination") }
      try? FileManager.default.removeItem(at: tempURL)
      return
    }

    do {
      _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
      if verbose { consolePrint("Metadata: applied") }
    } catch {
      if verbose { consolePrint("Metadata: failed to replace output file (\(error.localizedDescription))") }
      try? FileManager.default.removeItem(at: tempURL)
    }
  }

  private func consolePrint(_ message: String) {
    print(message)
  }

  private func defaultJobCount() -> Int {
    let perfCores = performanceCoreCount()
    let fallback = ProcessInfo.processInfo.activeProcessorCount
    return max(1, perfCores ?? fallback)
  }

  private func performanceCoreCount() -> Int? {
    if let perfPhysical = sysctlInt("hw.perflevel0.physicalcpu") {
      return perfPhysical
    }
    if let perfLogical = sysctlInt("hw.perflevel0.logicalcpu") {
      return perfLogical
    }
    if let physical = sysctlInt("hw.physicalcpu") {
      return physical
    }
    if let logical = sysctlInt("hw.logicalcpu") {
      return logical
    }
    return nil
  }

  private func sysctlInt(_ name: String) -> Int? {
    var value: Int = 0
    var size = MemoryLayout<Int>.size
    if sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 {
      return value
    }
    return nil
  }
}

extension ExportHEICCommand.ExportHEICCommandSignature {
  enum MyError: Error, CustomStringConvertible {
    var description: String {
      switch self {
      case .coexistencyNotAllowed(let label, let anotherArgumentLabel):
        return "`--\(label)` cannot be used with `--\(anotherArgumentLabel)`"
      case .missingEitherArgument(let labels):
        let flags = labels.map({ s in "--" + s }).joined(separator: ", ")
        return "One of \(flags) must be specified"
      case .missingArgument(let label):
        return "Missing required argument: `--\(label)`"
      }
    }

    case coexistencyNotAllowed(_ label: String, _ anotherArgumentLabel: String)
    case missingEitherArgument(_ labels: [String])
    case missingArgument(_ label: String)
  }

  func checkOptions() throws {
    let hasInputFile = inputFile != nil
    let hasInputDir = inputDir != nil

    if hasInputFile && hasInputDir {
      throw MyError.coexistencyNotAllowed("input-file", "input-dir")
    }
    if !hasInputFile && !hasInputDir {
      throw MyError.missingEitherArgument(["input-file", "input-dir"])
    }

    if quality != nil {
      if sizeLimit != nil { throw MyError.coexistencyNotAllowed("quality", "size-limit") }
      if minQuality != nil { throw MyError.coexistencyNotAllowed("quality", "min-quality") }
      if maxQuality != nil { throw MyError.coexistencyNotAllowed("quality", "max-quality") }
    } else if sizeLimit == nil {
      if minQuality != nil { throw MyError.coexistencyNotAllowed("min-quality", "size-limit") }
      if maxQuality != nil { throw MyError.coexistencyNotAllowed("max-quality", "size-limit") }
      // Both quality and size-limit missing: default quality will be used.
    }
  }
}
