#!/usr/bin/env swift

import Foundation
import Vision
import AppKit

// MARK: - Configuration
let RECOGNITION_LEVEL = VNRequestTextRecognitionLevel.accurate
let DEFAULT_LANGUAGES = ["zh-CN", "en-US"]

// MARK: - Usage Information
func printUsage() -> Never {
    let scriptName = (CommandLine.arguments[0] as NSString).lastPathComponent
    print("""
    Usage: \(scriptName) [options] [image_path]
    Options:
      -l, --language  Specify recognition languages (comma-separated, default: zh-CN,en-US)
      -f, --fast     Use fast recognition mode
      -v, --verbose  Show detailed processing information
      -h, --help     Show this help message
      --langs        List supported languages
    
    Example:
      \(scriptName) image.jpg              # Process image file
      \(scriptName) -l zh-CN,en-US image.jpg  # Specify languages
      \(scriptName) -f image.jpg          # Use fast mode
      cat image.jpg | \(scriptName)       # Read from stdin
    """)
    exit(1)
}

// MARK: - Main
// Show usage only if help is requested or invalid args provided
if CommandLine.arguments.count == 2 && (CommandLine.arguments[1] == "-h" || CommandLine.arguments[1] == "--help") {
    printUsage()
}

// MARK: - List Supported Languages
func listSupportedLanguages() -> Never {
    let request = VNRecognizeTextRequest()
    if let languages = try? request.supportedRecognitionLanguages() {
        print("Supported languages:")
        languages.forEach { print("  \($0)") }
    } else {
        print("Failed to get supported languages")
    }
    exit(0)
}

// MARK: - Parse Arguments
func parseArguments() -> (path: String?, languages: [String], fast: Bool) {
    var args = Array(CommandLine.arguments.dropFirst())
    var languages = DEFAULT_LANGUAGES
    var fast = false
    var imagePath: String? = nil
    
    while !args.isEmpty {
        let arg = args.removeFirst()
        switch arg {
        case "--langs":
            listSupportedLanguages()
        case "-l", "--language":
            if args.isEmpty {
                print("Error: Language argument is missing")
                printUsage()
            }
            languages = args.removeFirst().split(separator: ",").map(String.init)
        case "-f", "--fast":
            fast = true
        case "-v", "--verbose":
            // This option is not used in the current implementation
            break
        case "-h", "--help":
            printUsage()
        default:
            imagePath = arg
        }
    }
    
    return (imagePath, languages, fast)
}

// MARK: - OCR Processing
func recognizeText(imageData: Data, languages: [String], fast: Bool) {
    guard let image = NSImage(data: imageData),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Error: Could not create image from input data")
        exit(1)
    }
    
    let handler = VNImageRequestHandler(cgImage: cgImage)
    let semaphore = DispatchSemaphore(value: 0)
    
    let request = VNRecognizeTextRequest { request, error in
        defer { semaphore.signal() }
        
        if let error = error {
            print("Error: \(error.localizedDescription)")
            exit(1)
        }
        
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            print("Error: No text observations found")
            return
        }
        
        // Process and print results
        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                print(candidate.string)
            }
        }
    }
    
    // Configure request
    request.recognitionLevel = fast ? .fast : .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = true
    
    do {
        try handler.perform([request])
        semaphore.wait()
    } catch {
        print("Error: \(error.localizedDescription)")
        exit(1)
    }
}

// MARK: - Main Execution
let (path, languages, fast) = parseArguments()

if let path = path {
    // Read from file
    if !FileManager.default.fileExists(atPath: path) {
        print("Error: File does not exist at path: \(path)")
        exit(1)
    }
    
    guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        print("Error: Could not read image data from file")
        exit(1)
    }
    
    recognizeText(imageData: imageData, languages: languages, fast: fast)
} else {
    // Read from stdin
    let stdin = FileHandle.standardInput
    var stdinData = Data()
    
    // Set stdin to non-blocking mode
    let fileDescriptor = stdin.fileDescriptor
    var flags = fcntl(fileDescriptor, F_GETFL, 0)
    guard flags >= 0 else {
        print("Error: Could not get file descriptor flags")
        exit(1)
    }
    flags |= O_NONBLOCK
    guard fcntl(fileDescriptor, F_SETFL, flags) >= 0 else {
        print("Error: Could not set non-blocking mode")
        exit(1)
    }
    
    // Read available data
    while true {
        do {
            if let data = try stdin.read(upToCount: 4096) {
                stdinData.append(data)
            } else {
                break
            }
        } catch {
            break
        }
    }
    
    // Check if we got any data
    if stdinData.isEmpty {
        print("Error: No input data received")
        printUsage()
    }
    
    recognizeText(imageData: stdinData, languages: languages, fast: fast)
} 