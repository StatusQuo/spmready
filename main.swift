#!/usr/bin/swift

import Foundation

// MARK: - NetworkKit

struct HttpResult {
    let code: Int
    let data: Data?
}

enum HttpError: Error {
    case error
}

extension Result {
    func take() -> Success? {
        switch self {
        case .success(let data):
            return data
        case .failure:
            return nil
        }
    }
}

func get(url: String) -> Result<HttpResult, HttpError> {

    var result: Result<HttpResult, HttpError> = .failure(HttpError.error)
    let semaphore = DispatchSemaphore(value: 0)
    let url = URL(string: url)!

    let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
        if let httpResponse = response as? HTTPURLResponse {
            result = .success(HttpResult(code: httpResponse.statusCode, data: data))
        }

        semaphore.signal()
    }

    task.resume()

    _ = semaphore.wait(timeout: .distantFuture)
    return result
}

// MARK: - RegexKit

enum Searcher: String {
   case cart = #"github ["']([A-Za-z0–9-]*)["']"#
   case pod = "pod [\"']([A-Za-z0–9-]*)[\"']"
   case podRepoUrl = "(((https?):((//)|(\\\\))+[\\w\\d:#@%/;$()~_?\\+-=\\\\.&]*))\">GitHub Repo</a>"
}

extension String {
    func match(_ search: Searcher) -> String? {
        let regex = NSRegularExpression(search.rawValue)
        if  let match = regex.matches(self), let matchRange = Range(match.range(at: 1), in: self) {
            let result = self[matchRange]
            return String(result)
        }
        return nil
    }
}

extension NSRegularExpression {
    convenience init(_ pattern: String) {
        do {
            try self.init(pattern: pattern)
        } catch {
            preconditionFailure("Illegal regular expression: \(pattern).")
        }
    }
}

extension NSRegularExpression {
    func matches(_ string: String) -> NSTextCheckingResult? {
        let range = NSRange(location: 0, length: string.utf16.count)
        return firstMatch(in: string, options: [], range: range)
    }
}

// MARK: - Helper functions

func fetchPods(_ path: String) -> [Library]? {
    var pods:[Library] = []
    do {
        // Get the contents
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let lines = contents.split(separator: "\n").map { String($0) }
        for line in lines {
            if let podName = line.match(.pod) {
                pods.append(Library(name: podName))
            }
            if let cartLib = line.match(.cart) {
                let lib = Library(name: cartLib)
                lib.repo = "https://github.com/" + lib.name
                pods.append(lib)
            }
        }
    }
    catch {
        print("Failed to open Podfile at \(path)")
        print("make sure the file exists")
        return nil
    }
    return pods

}

func fetchUrl(pod: String) -> String {

    let path = "https://cocoapods.org/pods/\(pod)"

    guard let data = get(url: path).take()?.data,
        let contents = String(data: data, encoding: .utf8) else {
        return ""
    }

    return contents

}


func hasSwiftPackageFile(repoUrl: String) -> Bool {
    let spmUrl = repoUrl.replacingOccurrences(of: ".git", with: "") + "/blob/master/Package.swift"

    if let code = get(url: spmUrl).take()?.code, code == 200 {
        return true
    }

    return false
}


func fetchRepoOnline(podName: String) -> String? {
    return fetchUrl(pod: podName).match(.podRepoUrl)
}


// MARK: - Data model

class Library {
    init(name: String) {
        self.name = name
    }

    let name: String
    var repo: String?
    var spmready: Bool = false
}

extension Library {
    func readyOrNot() -> String {
        return spmready ? "✅" : "❌"
    }

    func format() -> String {
        return "\(self.readyOrNot()) | \(self.name) : \(self.repo ?? "not found")"
    }
}


// MARK: actual script

let path: String

if CommandLine.arguments.count == 2 {
    path = CommandLine.arguments[1]
} else {
    let arg = CommandLine.arguments.first!
    let workingFolder = String(arg.prefix(upTo: arg.lastIndex(of: "/")!))
    let podPath = workingFolder + "/Podfile"
    let cartPath = workingFolder + "/Cartfile"
    if FileManager.default.fileExists(atPath: podPath) {
        path = podPath
    } else if FileManager.default.fileExists(atPath: cartPath) {
        path = cartPath
    } else {
        path = ""
    }
}


// Set the file path

guard let pods = fetchPods(path) else {
    exit(1)
}

print("Found \(pods.count) pod")

for pod in pods {
    if pod.repo == nil, let url = fetchRepoOnline(podName: pod.name) {
        pod.repo = url
    }

    if let repo = pod.repo, hasSwiftPackageFile(repoUrl: repo) {
        pod.spmready = true
    }

    print(pod.format())

}

let ready = pods.filter { $0.spmready }.count
let notReady = pods.filter { !$0.spmready }.count

if ready == pods.count {
    print("🎊 you are ready for Swift Package Manager")
} else {
    print("Sorry 😢 - ✅ \(ready) | ❌ \(notReady)")
    print("Help to improve SPM capablility by opening an issue or contribute via a Pullrequest")
}



