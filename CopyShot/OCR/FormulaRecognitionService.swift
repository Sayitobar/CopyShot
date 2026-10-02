import AppKit
import OnnxRuntimeBindings

struct FormulaResult: Equatable, CustomStringConvertible {
    let formula: String
    let wasSyntaxFixed: Bool
    
    var description: String { formula }
    var isEmpty: Bool { formula.isEmpty }
    
    init(formula: String, wasSyntaxFixed: Bool = false) {
        self.formula = formula
        self.wasSyntaxFixed = wasSyntaxFixed
    }
}

protocol FormulaRecognizing: AnyObject {
    func prewarm()
    func recognize(_ image: CGImage, completion: @escaping (Result<FormulaResult, Error>) -> Void)
}

enum FormulaRecognitionError: LocalizedError {
    case missingResources(URL)
    case invalidModel(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingResources(let directory):
            "MFR 1.5 model files are missing from \(directory.path)."
        case .invalidModel(let detail):
            "MFR 1.5 model error: \(detail)"
        case .emptyResult:
            "No formula was recognized."
        }
    }
}

/// Runs only the Pix2Text MFR 1.5 encoder and decoder. No formula detector is involved.
/// Sessions load lazily and remain cached until 60 seconds idle or memory pressure.
final class FormulaRecognitionService: FormulaRecognizing {
    private let queue = DispatchQueue(label: "CopyShot.MFR", qos: .userInitiated)
    private lazy var modelCache = IdleModelCache(queue: queue, policy: initialPolicy, load: Self.loadModel)
    private let initialPolicy: ModelUnloadPolicy
    private let memoryPressure: DispatchSourceMemoryPressure
    private var policyObserver: Any?

    init(policy: ModelUnloadPolicy = SettingsManager.shared.mfrUnloadPolicy) {
        self.initialPolicy = policy
        memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        memoryPressure.setEventHandler { [weak self] in
            self?.modelCache.release()
        }
        memoryPressure.resume()

        policyObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MFRUnloadPolicyChanged"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.updatePolicy(SettingsManager.shared.mfrUnloadPolicy)
        }
    }

    convenience init(modelIdleTimeout: TimeInterval) {
        self.init(policy: ModelUnloadPolicy(rawSeconds: modelIdleTimeout))
    }

    deinit {
        memoryPressure.cancel()
        if let policyObserver {
            NotificationCenter.default.removeObserver(policyObserver)
        }
    }

    func updatePolicy(_ policy: ModelUnloadPolicy) {
        queue.async { [weak self] in
            self?.modelCache.updatePolicy(policy)
        }
    }

    /// Loads and caches MFR ONNX sessions in the background, starting the idle eviction timer.
    func prewarm() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.modelCache.value()
                self.modelCache.scheduleIdleRelease()
            } catch {
                #if DEBUG
                debugPrint("[MFR 1.5] prewarm failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func recognize(_ image: CGImage, completion: @escaping (Result<FormulaResult, Error>) -> Void) {
        queue.async { [self] in
            defer { modelCache.scheduleIdleRelease() }
            let result = autoreleasepool { Result { try recognizeSync(image) } }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func loadModel() throws -> LoadedModel {
        #if DEBUG
        let loadStart = ContinuousClock.now
        #endif
        let model = try LoadedModel()
        #if DEBUG
        debugPrint(String(format: "[MFR 1.5] model load %.1f ms", CaptureBenchmarkTracker.milliseconds(ContinuousClock.now - loadStart)))
        #endif
        return model
    }

    private func recognizeSync(_ image: CGImage) throws -> FormulaResult {
        let model = try modelCache.value()
        let start = CFAbsoluteTimeGetCurrent()
        let pixelValues = try Self.preprocess(image)
        let encoderInput = try Self.value(pixelValues, shape: [1, 3, 384, 384])
        let encoded = try model.encoder.run(withInputs: ["pixel_values": encoderInput],
                                            outputNames: [model.encoderOutput], runOptions: nil)
        guard let hidden = encoded[model.encoderOutput] else {
            throw FormulaRecognitionError.invalidModel("Encoder output missing")
        }

        var ids: [Int64] = [1] // MFR 1.5 decoder_start_token_id
        var reachedEndToken = false
        for _ in 0..<1024 {
            // Decoder tensors are temporary; drain their Objective-C autoreleases each token.
            let next = try autoreleasepool {
                let inputIDs = try Self.value(ids, shape: [1, NSNumber(value: ids.count)])
                let outputs = try model.decoder.run(withInputs: [
                    "input_ids": inputIDs,
                    "encoder_hidden_states": hidden
                ], outputNames: [model.decoderOutput], runOptions: nil)
                guard let output = outputs[model.decoderOutput] else {
                    throw FormulaRecognitionError.invalidModel("Decoder output missing")
                }
                return try Self.greedyLastToken(output)
            }
            if next == 2 {
                reachedEndToken = true
                break
            } // eos_token_id
            ids.append(next)
        }
        guard reachedEndToken else { throw FormulaRecognitionError.invalidModel("Generation reached the token limit") }
        let rawLatex = model.tokenizer.decode(Array(ids.dropFirst()))
        guard !rawLatex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FormulaRecognitionError.emptyResult
        }
        
        let settings = SettingsManager.shared
        var latex = rawLatex
        var wasSyntaxFixed = false
        
        if settings.fixLatexSyntax {
            let fixedResult = LaTeXNormalizer.fixSyntax(latex)
            latex = fixedResult.fixed
            wasSyntaxFixed = fixedResult.wasFixed
        }
        
        if settings.prettifyLatex {
            latex = LaTeXNormalizer.prettify(latex)
        }
        
        #if DEBUG
        debugPrint(String(format: "[MFR 1.5] inference %.1f ms (%d tokens)%@",
                          (CFAbsoluteTimeGetCurrent() - start) * 1_000, ids.count - 1,
                          wasSyntaxFixed ? " [syntax fixed]" : ""))
        #endif
        return FormulaResult(formula: latex, wasSyntaxFixed: wasSyntaxFixed)
    }

    private static func value<T>(_ values: [T], shape: [NSNumber], type: ORTTensorElementDataType) throws -> ORTValue {
        let data = values.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<T>.stride)
        }
        return try ORTValue(tensorData: NSMutableData(data: data), elementType: type, shape: shape)
    }

    private static func value(_ values: [Float], shape: [NSNumber]) throws -> ORTValue {
        try value(values, shape: shape, type: .float)
    }

    private static func value(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        try value(values, shape: shape, type: .int64)
    }

    private static func greedyLastToken(_ output: ORTValue) throws -> Int64 {
        let shape = try output.tensorTypeAndShapeInfo().shape.map(\.intValue)
        guard shape.count == 3, let vocabularySize = shape.last, vocabularySize > 0 else {
            throw FormulaRecognitionError.invalidModel("Unexpected decoder logits shape")
        }
        let data = try output.tensorData()
        let scoreCount = data.length / MemoryLayout<Float>.stride
        guard scoreCount >= vocabularySize else {
            throw FormulaRecognitionError.invalidModel("Decoder logits are incomplete")
        }
        // Only the final position is needed. Avoid copying every position's vocabulary.
        let scores = data.bytes.assumingMemoryBound(to: Float.self)
        let offset = scoreCount - vocabularySize
        var winner = 0
        for index in 1..<vocabularySize where scores[offset + winner] < scores[offset + index] {
            winner = index
        }
        return Int64(winner)
    }

    static func preprocess(_ image: CGImage) throws -> [Float] {
        let side = 384
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let success = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard success else { throw FormulaRecognitionError.invalidModel("Could not preprocess image") }
        // DeiTImageProcessor for this model: RGB, 384², rescale by 1/255,
        // normalize with mean and standard deviation 0.5, channel-first.
        var tensor = [Float](repeating: 0, count: 3 * side * side)
        for pixel in 0..<(side * side) {
            for channel in 0..<3 {
                tensor[channel * side * side + pixel] = Float(pixels[pixel * 4 + channel]) / 127.5 - 1
            }
        }
        return tensor
    }
}

private final class LoadedModel {
    let environment: ORTEnv
    let encoder: ORTSession
    let decoder: ORTSession
    let encoderOutput: String
    let decoderOutput: String
    let tokenizer: MFRTokenizer

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopyShot/MFR-1.5", isDirectory: true)
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("MFR-1.5", isDirectory: true)
        let override = ProcessInfo.processInfo.environment["COPYSHOT_MFR_MODEL_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let directory = override ?? bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? appSupport
        let encoderURL = directory.appendingPathComponent("encoder_model.onnx")
        let decoderURL = directory.appendingPathComponent("decoder_model.onnx")
        let tokenizerURL = directory.appendingPathComponent("tokenizer.json")
        guard [encoderURL, decoderURL, tokenizerURL].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw FormulaRecognitionError.missingResources(directory)
        }
        environment = try ORTEnv(loggingLevel: .warning)
        encoder = try ORTSession(env: environment, modelPath: encoderURL.path, sessionOptions: nil)
        decoder = try ORTSession(env: environment, modelPath: decoderURL.path, sessionOptions: nil)
        guard let encoderOutput = try encoder.outputNames().first,
              let decoderOutput = try decoder.outputNames().first else {
            throw FormulaRecognitionError.invalidModel("Model outputs unavailable")
        }
        self.encoderOutput = encoderOutput
        self.decoderOutput = decoderOutput
        tokenizer = try MFRTokenizer(url: tokenizerURL)
    }
}

/// Decodes the model's XLM-R ByteLevel BPE IDs without requiring a Python tokenizer.
private struct MFRTokenizer {
    private let tokens: [Int: String]
    private let byteForScalar: [UnicodeScalar: UInt8]

    init(url: URL) throws {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        guard let model = root?["model"] as? [String: Any],
              let vocabulary = model["vocab"] as? [String: Int] else {
            throw FormulaRecognitionError.invalidModel("Invalid tokenizer.json")
        }
        tokens = Dictionary(uniqueKeysWithValues: vocabulary.map { ($0.value, $0.key) })
        let direct = Array(33...126) + Array(161...172) + Array(174...255)
        var mapping: [UnicodeScalar: UInt8] = [:]
        for byte in direct { mapping[UnicodeScalar(byte)!] = UInt8(byte) }
        var extra = 0
        for byte in 0...255 where !direct.contains(byte) {
            mapping[UnicodeScalar(256 + extra)!] = UInt8(byte)
            extra += 1
        }
        byteForScalar = mapping
    }

    func decode(_ ids: [Int64]) -> String {
        var bytes: [UInt8] = []
        for id in ids where id > 4 {
            guard let token = tokens[Int(id)] else { continue }
            for scalar in token.unicodeScalars {
                if let byte = byteForScalar[scalar] { bytes.append(byte) }
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
