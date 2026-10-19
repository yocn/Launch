import CoreGraphics

enum PageDragResolver {
    static let turnFraction: CGFloat = 0.3
    static let edgeResistance: CGFloat = 0.3

    static func displayOffset(translation: CGFloat, currentPage: Int, pageCount: Int) -> CGFloat {
        let pastFirst = currentPage <= 0 && translation > 0
        let pastLast = currentPage >= pageCount - 1 && translation < 0
        return pastFirst || pastLast ? translation * edgeResistance : translation
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
