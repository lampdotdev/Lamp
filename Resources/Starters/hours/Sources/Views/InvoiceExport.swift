import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Turns an invoice page into a PDF, to save or to print.
@MainActor
enum InvoiceExport {
    /// One PDF page, as long as the invoice needs (at least a US Letter page).
    static func pdf(_ invoice: Invoice) -> Data {
        let renderer = ImageRenderer(content: InvoicePage(invoice: invoice))
        let data = NSMutableData()
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: InvoicePage.width, height: max(792, size.height))
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            // PDF pages grow upward: put the content at the top of the page.
            context.translateBy(x: 0, y: box.height - size.height)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data as Data
    }

    /// Asks where to save, then writes the PDF. True when it was saved.
    static func save(_ invoice: Invoice) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(invoice.number) \(invoice.client.name).pdf"
            .replacingOccurrences(of: "/", with: "-")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try pdf(invoice).write(to: url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    static func print(_ invoice: Invoice) {
        guard let document = PDFDocument(data: pdf(invoice)) else { return }
        // A copy, so the margins don't change for every other print.
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: false)?.run()
    }
}
