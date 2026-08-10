import Foundation

/// 体重记录导出 CSV(UTF-8 with BOM,Excel/Numbers 中文不乱码)
enum CSVExporter {
    static let header = String(localized: "日期,体重(kg)")

    /// 生成 CSV 到临时目录,返回文件 URL;失败返回 nil
    static func exportWeightCSV(
        from entries: [MetricEntry],
        fileName: String = String(localized: "衡-体重记录.csv")
    ) -> URL? {
        let weightEntries = entries
            .filter { $0.metric == .weight }
            .sorted { $0.date < $1.date }

        var csv = "\u{FEFF}" + header + "\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        for entry in weightEntries {
            csv += "\(dateFormatter.string(from: entry.date)),\(StatsCalculator.format1(entry.value))\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
