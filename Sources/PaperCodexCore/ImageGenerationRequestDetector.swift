import Foundation

public enum ImageGenerationRequestDetector {
    public static func isImageRequest(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let strongEnglishTriggers = [
            "generate an image",
            "create an image",
            "make an image",
            "draw a",
            "make a diagram",
            "create a diagram",
            "generate a diagram",
            "make an infographic",
            "create an infographic",
            "generate an infographic"
        ]
        if strongEnglishTriggers.contains(where: { lowercased.contains($0) }) {
            return true
        }

        let strongChineseTriggers = [
            "生成一张图",
            "生成图片",
            "画一张图",
            "做一张图",
            "出一张图",
            "生成示意图",
            "画示意图",
            "做示意图",
            "生成流程图",
            "画流程图",
            "做流程图",
            "生成信息图"
        ]
        if strongChineseTriggers.contains(where: { text.contains($0) }) {
            return true
        }

        return false
    }
}
