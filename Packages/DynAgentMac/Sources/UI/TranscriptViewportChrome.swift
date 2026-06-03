import AppKit

enum TranscriptViewportChrome {
    static let transcriptSpacing: CGFloat = 12
    static let initialBottomInset: CGFloat = 96
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 12

    static func configureTranscript(_ transcript: NSStackView) {
        transcript.orientation = .vertical
        transcript.alignment = .leading
        transcript.spacing = transcriptSpacing
        transcript.translatesAutoresizingMaskIntoConstraints = false
        transcript.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        transcript.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    static func makeDocument(containing transcript: NSStackView) -> FlippedView {
        let document = FlippedView()
        document.addSubview(transcript)
        document.translatesAutoresizingMaskIntoConstraints = false
        document.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        document.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return document
    }

    static func configureScroll(_ scroll: NSScrollView, document: NSView) {
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: initialBottomInset, right: 0)
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    static func constraints(
        scroll: NSScrollView,
        root: NSView,
        document: NSView,
        transcript: NSStackView,
        horizontalInset: CGFloat = ChatLayoutModel.horizontalInset,
        maxReadableWidth: CGFloat = ChatLayoutModel.maxReadableWidth
    ) -> [NSLayoutConstraint] {
        let fillWidth = transcript.widthAnchor.constraint(equalTo: document.widthAnchor, constant: -(horizontalInset * 2))
        fillWidth.priority = .defaultHigh
        return [
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.widthAnchor.constraint(equalTo: root.widthAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),

            transcript.topAnchor.constraint(equalTo: document.topAnchor, constant: topPadding),
            transcript.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -bottomPadding),
            transcript.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: horizontalInset),
            transcript.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -horizontalInset),
            transcript.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            transcript.widthAnchor.constraint(lessThanOrEqualToConstant: maxReadableWidth),
            fillWidth,
        ]
    }
}
