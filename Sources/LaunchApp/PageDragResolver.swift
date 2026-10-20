import CoreGraphics

enum PageDragResolver {
    static let turnFraction: CGFloat = 0.3
    static let edgeResistance: CGFloat = 0.3

    // 按内容实际位置算阻尼，从中间页长距离拖过首页或末页时同样生效
    static func displayOffset(translation: CGFloat, currentPage: Int, pageCount: Int, pageWidth: CGFloat) -> CGFloat {
        let firstEdge = CGFloat(max(currentPage, 0)) * pageWidth
        let lastEdge = -CGFloat(max(pageCount - 1 - currentPage, 0)) * pageWidth
        if translation > firstEdge {
            return firstEdge + (translation - firstEdge) * edgeResistance
        }
        if translation < lastEdge {
            return lastEdge + (translation - lastEdge) * edgeResistance
        }
        return translation
    }

    static func targetPage(
        currentPage: Int,
        pageCount: Int,
        predictedTranslation: CGFloat,
        pageWidth: CGFloat
    ) -> Int {
        guard pageCount > 0, pageWidth > 0 else {
            return currentPage
        }
        let threshold = pageWidth * turnFraction
        if predictedTranslation <= -threshold {
            return min(currentPage + 1, pageCount - 1)
        }
        if predictedTranslation >= threshold {
            return max(currentPage - 1, 0)
        }
        return currentPage
    }
}
