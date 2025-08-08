import SwiftUI

struct MarkdownRenderer: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseBlocks(text), id: \.id) { block in
                switch block.kind {
                case .code(let code, _):
                    CodeBlockView(code: code)
                case .table(let table):
                    MarkdownTableView(table: table)
                case .paragraph(let para):
                    if let att = try? AttributedString(markdown: para) {
                        Text(att)
                    } else {
                        Text(para)
                    }
                }
            }
        }
    }

    private func parseBlocks(_ input: String) -> [Block] {
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [Block] = []
        var i = 0
        func pushParagraph(_ buf: inout [String]) {
            if !buf.isEmpty {
                blocks.append(Block(kind: .paragraph(buf.joined(separator: "\n"))))
                buf.removeAll()
            }
        }
        var paragraphBuf: [String] = []
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("```") {
                // code fence
                let fence = line
                let lang = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var code = ""
                while i < lines.count, !lines[i].hasPrefix("```") {
                    code.append(lines[i])
                    code.append("\n")
                    i += 1
                }
                // consume closing fence
                if i < lines.count { i += 1 }
                pushParagraph(&paragraphBuf)
                blocks.append(Block(kind: .code(code, lang.isEmpty ? nil : lang)))
                continue
            }
            // table detection: header | a | b ; separator | --- | --- ; then rows
            if line.contains("|") && i + 1 < lines.count {
                let header = line
                let sep = lines[i + 1]
                if isTableSeparator(sep) {
                    var rows: [String] = []
                    i += 2
                    while i < lines.count, lines[i].contains("|") && !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        rows.append(lines[i])
                        i += 1
                    }
                    pushParagraph(&paragraphBuf)
                    if let table = parseTable(header: header, separator: sep, rows: rows) {
                        blocks.append(Block(kind: .table(table)))
                        continue
                    }
                }
            }
            // paragraph line
            paragraphBuf.append(line)
            i += 1
        }
        pushParagraph(&paragraphBuf)
        return blocks
    }

    private func isTableSeparator(_ line: String) -> Bool {
        // A valid separator looks like: | --- | :---: | ---: |
        let parts = splitTableLine(line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return false }
            // allow colons for alignment
            let stripped = t.replacingOccurrences(of: ":", with: "")
            return stripped.allSatisfy { $0 == "-" }
        }
    }

    private func splitTableLine(_ line: String) -> [String] {
        // Split by '|' and drop first/last if empty due to edge pipes
        var parts = line.split(separator: "|").map { String($0) }
        // trim spaces
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }
        // drop leading/trailing empties introduced by edge pipes
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private func parseTable(header: String, separator: String, rows: [String]) -> TableData? {
        let headers = splitTableLine(header)
        guard !headers.isEmpty else { return nil }
        var body: [[String]] = []
        for r in rows {
            let cols = splitTableLine(r)
            if cols.isEmpty { continue }
            let padded = cols + Array(repeating: "", count: max(0, headers.count - cols.count))
            body.append(Array(padded.prefix(headers.count)))
        }
        return TableData(headers: headers, rows: body)
    }

    struct Block: Identifiable {
        let id = UUID()
        let kind: Kind
        enum Kind {
            case code(String, String?)
            case table(TableData)
            case paragraph(String)
        }
    }
}

struct TableData {
    let headers: [String]
    let rows: [[String]]
}

private struct MarkdownTableView: View {
    let table: TableData
    var body: some View {
        VStack(spacing: 0) {
            // header
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { idx, h in
                    cellView(h, isHeader: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(Rectangle().fill(Color(.separator)).frame(width: 0.5), alignment: .trailing)
                }
            }
            .background(Color(.secondarySystemBackground))
            .overlay(Rectangle().fill(Color(.separator)).frame(height: 0.5), alignment: .bottom)

            // rows
            ForEach(Array(table.rows.enumerated()), id: \.offset) { ridx, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<table.headers.count, id: \.self) { c in
                        let txt = c < row.count ? row[c] : ""
                        cellView(txt, isHeader: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(Rectangle().fill(Color(.separator)).frame(width: 0.5), alignment: .trailing)
                    }
                }
                .background(ridx % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground).opacity(0.4))
                .overlay(Rectangle().fill(Color(.separator)).frame(height: 0.5), alignment: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func cellView(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(isHeader ? .headline : .body)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .minimumScaleFactor(0.85)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
    }
}

private struct CodeBlockView: View {
    let code: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

