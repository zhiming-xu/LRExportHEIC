import ConsoleKit
import Foundation

let console: Console = Terminal()
let arguments = preprocessArguments(CommandLine.arguments)
var input = CommandInput(arguments: arguments)
var context = CommandContext(console: console, input: input)

do {
  try console.run(ExportHEICCommand(), input: input)
} catch {
  console.error("\(error)")
  exit(1)
}

private func preprocessArguments(_ arguments: [String]) -> [String] {
  guard shouldInjectOutputPlaceholder(arguments) else {
    return arguments
  }

  var updated = arguments
  updated.append("__OUTPUT_PLACEHOLDER__")
  return updated
}

private func shouldInjectOutputPlaceholder(_ arguments: [String]) -> Bool {
  if arguments.contains("--help") || arguments.contains("-h") {
    return false
  }
  guard arguments.contains("--input-dir") else {
    return false
  }

  let optionsWithValues: Set<String> = [
    "--input-file",
    "--input-dir",
    "--quality",
    "--size-limit",
    "--min-quality",
    "--max-quality",
    "--color-space",
    "--jobs",
  ]
  let flags: Set<String> = [
    "--verbose",
  ]

  var index = 1
  while index < arguments.count {
    let arg = arguments[index]
    if optionsWithValues.contains(arg) {
      index += 2
      continue
    }
    if flags.contains(arg) {
      index += 1
      continue
    }
    if arg.hasPrefix("-") {
      index += 1
      continue
    }
    return false
  }

  return true
}
