import Foundation
import UIKit
import Display
import AccountContext
import TelegramCore

private func entitiesPath() -> String {
    return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/mediaEntities"
}

private func fullEntityMediaPath(_ path: String) -> String {
    return NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] + "/mediaEntities/" + path
}

public final class DrawingStickerEntity: DrawingEntity, Codable {
    public enum Content: Equatable {
        case file(TelegramMediaFile)
        case image(UIImage, Bool)
        case video(String, UIImage?, Bool)
        case dualVideoReference
        
        public static func == (lhs: Content, rhs: Content) -> Bool {
            switch lhs {
            case let .file(lhsFile):
                if case let .file(rhsFile) = rhs {
                    return lhsFile.fileId == rhsFile.fileId
                } else {
                    return false
                }
            case let .image(lhsImage, lhsIsRectangle):
                if case let .image(rhsImage, rhsIsRectangle) = rhs {
                    return lhsImage === rhsImage && lhsIsRectangle == rhsIsRectangle
                } else {
                    return false
                }
            case let .video(lhsPath, _, lhsInternalMirrored):
                if case let .video(rhsPath, _, rhsInternalMirrored) = rhs {
                    return lhsPath == rhsPath && lhsInternalMirrored == rhsInternalMirrored
                } else {
                    return false
                }
            case .dualVideoReference:
                if case .dualVideoReference = rhs {
                    return true
                } else {
                    return false
                }
            }
        }
    }
    private enum CodingKeys: String, CodingKey {
        case uuid
        case file
        case imagePath
        case videoPath
        case videoImagePath
        case videoMirrored
        case isRectangle
        case dualVideo
        case referenceDrawingSize
        case position
        case scale
        case rotation
        case mirrored
        case isExplicitlyStatic
    }
    
    public let uuid: UUID
    public let content: Content
    
    public var referenceDrawingSize: CGSize
    public var position: CGPoint
    public var scale: CGFloat
    public var rotation: CGFloat
    public var mirrored: Bool
    
    public var isExplicitlyStatic: Bool
        
    public var color: DrawingColor = DrawingColor.clear
    public var lineWidth: CGFloat = 0.0
    
    public var center: CGPoint {
        return self.position
    }
    
    public var baseSize: CGSize {
        let size = max(10.0, min(self.referenceDrawingSize.width, self.referenceDrawingSize.height) * 0.25)
        return CGSize(width: size, height: size)
    }
    
    public var isAnimated: Bool {
        switch self.content {
        case let .file(file):
            if self.isExplicitlyStatic {
                return false
            } else {
                return file.isAnimatedSticker || file.isVideoSticker || file.mimeType == "video/webm"
            }
        case .image:
            return false
        case .video:
            return true
        case .dualVideoReference:
            return true
        }
    }
    
    public var isRectangle: Bool {
        switch self.content {
        case let .image(_, isRectangle):
            return isRectangle
        default:
            return false
        }
    }
    
    public var isMedia: Bool {
        return false
    }
    
    public var renderImage: UIImage?
    public var renderSubEntities: [DrawingEntity]?
    
    public init(content: Content) {
        self.uuid = UUID()
        self.content = content
        
        self.referenceDrawingSize = .zero
        self.position = CGPoint()
        self.scale = 1.0
        self.rotation = 0.0
        self.mirrored = false
        
        self.isExplicitlyStatic = false
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.uuid = try container.decode(UUID.self, forKey: .uuid)
        if let _ = try container.decodeIfPresent(Bool.self, forKey: .dualVideo) {
            self.content = .dualVideoReference
        } else if let file = try container.decodeIfPresent(TelegramMediaFile.self, forKey: .file) {
            self.content = .file(file)
        } else if let imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath), let image = UIImage(contentsOfFile: fullEntityMediaPath(imagePath)) {
            let isRectangle = try container.decodeIfPresent(Bool.self, forKey: .isRectangle) ?? false
            self.content = .image(image, isRectangle)
        } else if let videoPath = try container.decodeIfPresent(String.self, forKey: .videoPath) {
            var imageValue: UIImage?
            if let imagePath = try container.decodeIfPresent(String.self, forKey: .videoImagePath), let image = UIImage(contentsOfFile: fullEntityMediaPath(imagePath)) {
                imageValue = image
            }
            let videoMirrored = try container.decodeIfPresent(Bool.self, forKey: .videoMirrored) ?? false
            self.content = .video(videoPath, imageValue, videoMirrored)
        } else {
            fatalError()
        }
        self.referenceDrawingSize = try container.decode(CGSize.self, forKey: .referenceDrawingSize)
        self.position = try container.decode(CGPoint.self, forKey: .position)
        self.scale = try container.decode(CGFloat.self, forKey: .scale)
        self.rotation = try container.decode(CGFloat.self, forKey: .rotation)
        self.mirrored = try container.decode(Bool.self, forKey: .mirrored)
        self.isExplicitlyStatic = try container.decodeIfPresent(Bool.self, forKey: .isExplicitlyStatic) ?? false
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.uuid, forKey: .uuid)
        switch self.content {
        case let .file(file):
            try container.encode(file, forKey: .file)
        case let .image(image, isRectangle):
            let imagePath = "\(self.uuid).png"
            let fullImagePath = fullEntityMediaPath(imagePath)
            if let imageData = image.pngData() {
                try? FileManager.default.createDirectory(atPath: entitiesPath(), withIntermediateDirectories: true)
                try? imageData.write(to: URL(fileURLWithPath: fullImagePath))
                try container.encodeIfPresent(imagePath, forKey: .imagePath)
            }
            try container.encode(isRectangle, forKey: .isRectangle)
        case let .video(path, image, videoMirrored):
            try container.encode(path, forKey: .videoPath)
            let imagePath = "\(self.uuid).jpg"
            let fullImagePath = fullEntityMediaPath(imagePath)
            if let imageData = image?.jpegData(compressionQuality: 0.87) {
                try? FileManager.default.createDirectory(atPath: entitiesPath(), withIntermediateDirectories: true)
                try? imageData.write(to: URL(fileURLWithPath: fullImagePath))
                try container.encodeIfPresent(imagePath, forKey: .videoImagePath)
            }
            try container.encode(videoMirrored, forKey: .videoMirrored)
        case .dualVideoReference:
            try container.encode(true, forKey: .dualVideo)
        }
        try container.encode(self.referenceDrawingSize, forKey: .referenceDrawingSize)
        try container.encode(self.position, forKey: .position)
        try container.encode(self.scale, forKey: .scale)
        try container.encode(self.rotation, forKey: .rotation)
        try container.encode(self.mirrored, forKey: .mirrored)
        try container.encode(self.isExplicitlyStatic, forKey: .isExplicitlyStatic)
    }
        
    public func duplicate() -> DrawingEntity {
        let newEntity = DrawingStickerEntity(content: self.content)
        newEntity.referenceDrawingSize = self.referenceDrawingSize
        newEntity.position = self.position
        newEntity.scale = self.scale
        newEntity.rotation = self.rotation
        newEntity.mirrored = self.mirrored
        newEntity.isExplicitlyStatic = self.isExplicitlyStatic
        return newEntity
    }
    
    public func isEqual(to other: DrawingEntity) -> Bool {
        guard let other = other as? DrawingStickerEntity else {
            return false
        }
        if self.uuid != other.uuid {
            return false
        }
        if self.content != other.content {
            return false
        }
        if self.referenceDrawingSize != other.referenceDrawingSize {
            return false
        }
        if self.position != other.position {
            return false
        }
        if self.scale != other.scale {
            return false
        }
        if self.rotation != other.rotation {
            return false
        }
        if self.mirrored != other.mirrored {
            return false
        }
        if self.isExplicitlyStatic != other.isExplicitlyStatic {
            return false
        }
        return true
    }
}
