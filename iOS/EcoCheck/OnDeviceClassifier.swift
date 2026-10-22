import CoreML
import Foundation
import ImageIO
import Vision

struct RecyclingGuide: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let material: String
    let steps: [String]
    let note: String

    static func load() throws -> [RecyclingGuide] {
        guard let url = Bundle.main.url(forResource: "recycling-guides", withExtension: "json") else {
            throw ClassificationError.missingGuides
        }
        return try JSONDecoder().decode([RecyclingGuide].self, from: Data(contentsOf: url))
    }
}

struct Classification: Sendable {
    let guide: RecyclingGuide
    let confidence: Double
    let modelVersion: String
}

enum ClassificationError: LocalizedError {
    case missingModel, missingGuides, invalidModel, invalidImage, uncertain
    var errorDescription: String? {
        switch self {
        case .missingModel: "아직 AI 모델이 준비되지 않았어요. 학습한 모델을 추가하면 이 아이폰에서 사진을 분석할 수 있어요."
        case .missingGuides: "분리배출 안내 파일을 찾을 수 없어요."
        case .invalidModel: "모델의 분류 형식 또는 버전 정보를 확인해주세요."
        case .invalidImage: "사진을 읽을 수 없어요. 다른 사진을 선택해주세요."
        case .uncertain: "확실하게 판별하지 못했어요. 밝은 곳에서 쓰레기를 하나씩 촬영해주세요."
        }
    }
}

// This actor performs Vision/Core ML work away from the main UI actor.
// There is no network request and no fallback to a made-up classification.
actor OnDeviceClassifier {
    static let shared = OnDeviceClassifier()
    private var visionModel: VNCoreMLModel?
    private var modelVersion = ""

    func classify(_ imageData: Data) throws -> Classification {
        try Task.checkCancellation()
        if visionModel == nil {
            guard let url = Bundle.main.url(forResource: "WasteClassifier", withExtension: "mlmodelc") else {
                throw ClassificationError.missingModel
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: url, configuration: configuration)
            guard let version = model.modelDescription.metadata[.versionString] as? String,
                  version.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", options: .regularExpression) != nil,
                  model.modelDescription.predictedFeatureName != nil else {
                throw ClassificationError.invalidModel
            }
            modelVersion = version
            visionModel = try VNCoreMLModel(for: model)
        }
        guard let visionModel else { throw ClassificationError.invalidModel }
        // Decode and rotate a bounded thumbnail rather than a full-resolution camera image.
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw ClassificationError.invalidImage }
        let request = VNCoreMLRequest(model: visionModel)
        // The training/export preprocessing must use the same crop strategy.
        request.imageCropAndScaleOption = .centerCrop
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        try Task.checkCancellation()
        guard let observations = request.results as? [VNClassificationObservation],
              let best = observations.max(by: { $0.confidence < $1.confidence }),
              best.confidence.isFinite, best.confidence >= 0.7, best.confidence <= 1,
              let guide = try RecyclingGuide.load().first(where: { $0.id == best.identifier }) else {
            throw ClassificationError.uncertain
        }
        return Classification(guide: guide, confidence: Double(best.confidence), modelVersion: modelVersion)
    }
}
