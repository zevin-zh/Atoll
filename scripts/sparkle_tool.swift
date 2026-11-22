#!/usr/bin/env swift
//
// Sparkle 工具：生成 EdDSA(Ed25519) 密钥对 / 给 dmg 签名并更新 appcast。
// 不依赖 Sparkle 的 generate_keys、generate_appcast（SPM 包里没有预编译二进制）。
//
// 用法：
//   swift scripts/sparkle_tool.swift genkey
//   swift scripts/sparkle_tool.swift update \
//       --appcast Updates/appcast.xml \
//       --dmg build/Z-island-1.0.1.dmg \
//       --version 1.0.1 --build 1941 \
//       --url https://github.com/zevin-zh/Z-island/releases/download/v1.0.1/Z-island-1.0.1.dmg \
//       --key-file ~/private_keys/sparkle_ed.key \
//       [--min-system 15.0] [--notes-file build/release_notes.md]
//
// 密钥格式与 Sparkle 一致：私钥文件是 base64(32 字节种子) 单行，
// 公钥 base64 写进 Info.plist 的 SUPublicEDKey。
//

import Foundation
import CryptoKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("ERROR: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func argValue(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func loadPrivateKey(path: String) -> Curve25519.Signing.PrivateKey {
    let expanded = (path as NSString).expandingTildeInPath
    guard let text = try? String(contentsOfFile: expanded, encoding: .utf8) else {
        fail("读不到私钥文件：\(expanded)")
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let seed = Data(base64Encoded: trimmed), seed.count == 32 else {
        fail("私钥格式不对（应为 base64 的 32 字节种子）：\(expanded)")
    }
    do {
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    } catch {
        fail("私钥无法载入：\(error)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("用法：sparkle_tool.swift <genkey|update> [参数]")
}

switch command {
case "genkey":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE_KEY=\(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC_KEY=\(key.publicKey.rawRepresentation.base64EncodedString())")

case "update":
    guard let appcastPath = argValue("--appcast", in: args),
          let dmgPath = argValue("--dmg", in: args),
          let version = argValue("--version", in: args),
          let build = argValue("--build", in: args),
          let url = argValue("--url", in: args),
          let keyFile = argValue("--key-file", in: args)
    else {
        fail("缺少参数：--appcast --dmg --version --build --url --key-file")
    }

    let key = loadPrivateKey(path: keyFile)

    let dmgURL = URL(fileURLWithPath: (dmgPath as NSString).expandingTildeInPath)
    guard let dmgData = try? Data(contentsOf: dmgURL) else {
        fail("读不到 dmg：\(dmgPath)")
    }

    let signature: Data
    do {
        signature = try key.signature(for: dmgData)
    } catch {
        fail("签名失败：\(error)")
    }

    // 自检：用公钥验一遍，签名不可用就别把 appcast 写出去
    guard key.publicKey.isValidSignature(signature, for: dmgData) else {
        fail("EdDSA 自检失败，签名与 dmg 不匹配")
    }

    let minSystem = argValue("--min-system", in: args) ?? "15.0"
    let notes: String
    if let notesFile = argValue("--notes-file", in: args),
       let text = try? String(contentsOfFile: (notesFile as NSString).expandingTildeInPath, encoding: .utf8) {
        notes = text.replacingOccurrences(of: "]]>", with: "]]&gt;")
    } else {
        notes = ""
    }

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    let pubDate = dateFormatter.string(from: Date())

    let escapedURL = url.replacingOccurrences(of: "&", with: "&amp;")

    // 每行手写缩进，避免多行字符串的缩进规则把 <item> 排歪
    let itemLines: [String] = [
        "<item>",
        "    <title>\(version)</title>",
        "    <pubDate>\(pubDate)</pubDate>",
        "    <sparkle:version>\(build)</sparkle:version>",
        "    <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>",
        "    <sparkle:minimumSystemVersion>\(minSystem)</sparkle:minimumSystemVersion>",
        "    <description><![CDATA[\(notes)]]></description>",
        "    <enclosure",
        "        url=\"\(escapedURL)\"",
        "        length=\"\(dmgData.count)\"",
        "        type=\"application/octet-stream\"",
        "        sparkle:edSignature=\"\(signature.base64EncodedString())\" />",
        "</item>",
    ]
    let item = itemLines.map { "    " + $0 }.joined(separator: "\n") + "\n"

    let appcastURL = URL(fileURLWithPath: (appcastPath as NSString).expandingTildeInPath)
    var xml: String

    if let existing = try? String(contentsOf: appcastURL, encoding: .utf8),
       existing.contains("<channel>") {
        xml = existing
        // 先删掉同版本号的旧条目，避免重复
        let pattern = "<item>(?:(?!</item>).)*?<sparkle:version>\(build)</sparkle:version>(?:(?!</item>).)*?</item>\\s*"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
            xml = regex.stringByReplacingMatches(in: xml, options: [], range: range, withTemplate: "")
        }
    } else {
        xml = """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
            <channel>
                <title>Z-island</title>
                <description>Z-island release feed</description>
                <language>zh-cn</language>
            </channel>
        </rss>

        """
    }

    guard let closingRange = xml.range(of: "</channel>") else {
        fail("appcast 里找不到 </channel>")
    }
    // 插到 </channel> 所在行的行首，保持缩进
    let lineStart = xml[..<closingRange.lowerBound].lastIndex(of: "\n")
        .map { xml.index(after: $0) } ?? xml.startIndex
    let closingLine = String(xml[lineStart..<closingRange.upperBound])
    xml.replaceSubrange(lineStart..<closingRange.upperBound, with: item + closingLine)

    do {
        try xml.write(to: appcastURL, atomically: true, encoding: .utf8)
    } catch {
        fail("写 appcast 失败：\(error)")
    }

    print("✅ \(version) (build \(build)) 写入 \(appcastPath)")
    print("   dmg \(dmgData.count) bytes · signature \(signature.base64EncodedString())")

default:
    fail("未知命令：\(command)")
}
