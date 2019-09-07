//
//  main.swift
//  pod2spm
//
//  Created by Sebastian Humann on 06.09.19.
//  Copyright © 2019 sipgate GmbH. All rights reserved.
//

import Foundation
import SwiftShell

class Pod {
    init(name: String) {
        self.name = name
    }

    let name: String
    var repo: String?
    var spmready: Bool = false

}

extension Pod {
    func readyOrNot() -> String {
        if spmready {
            return "✅"
        }
        return "❌"
    }

    func format() -> String {
        "\(self.readyOrNot()) | \(self.name) : \(self.repo ?? "not found")"
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

func fetchRepo(podName: String) -> String? {
    let date = run("/usr/local/bin/pod", "search", podName).stdout
    let lines = date.split(separator: "\n")
    for line in lines {
        let regex = NSRegularExpression("Source:(.*)")
        if  let match = regex.matches(String(line)), let repoRange = Range(match.range(at: 1), in: line) {
            let repoUrl = line[repoRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return repoUrl
        }
    }
    return nil
}

func fetchPods(_ path: String) -> [Pod] {
    var pods:[Pod] = []
    do {
        // Get the contents
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let lines = contents.split(separator: "\n")
        for line in lines {
            let regex = NSRegularExpression("pod '([A-Za-z0-9-]*)'")

            if  let match = regex.matches(String(line)), let podNameRange = Range(match.range(at: 1), in: line) {
                let podName = line[podNameRange]
                pods.append(Pod(name: String(podName)))

            }
        }
        //sprint(contents)
    }
    catch let error as NSError {
        print("Ooops! Something went wrong: \(error)")
    }
    return pods

}

func isSpmReady(pod: Pod) -> Bool {
    guard let repo = pod.repo else {
        return false
    }

    let spmUrl = repo.replacingOccurrences(of: ".git", with: "/blob/master/Package.swift")
   // print(spmUrl)

    var result = false
    let semaphore = DispatchSemaphore(value: 0)
    let url = URL(string: spmUrl)!

    let task = URLSession.shared.dataTask(with: url) {(data, response, error) in
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                result = true
            }
        }

        semaphore.signal()
    }

    task.resume()

    _ = semaphore.wait(timeout: .distantFuture)
    return result
}

// Set the file path
let path = "/Users/humann/git/satellite-app-ios/Podfile"

let pods = fetchPods(path)

print("Found \(pods.count) Pods")

for pod in pods {
    if let url = fetchRepo(podName: pod.name) {
        pod.repo = url
        if isSpmReady(pod: pod) {
            pod.spmready = true
        }
        print(pod.format())
    }
}

let ready = pods.filter { $0.spmready }.count
let notReady = pods.filter { !$0.spmready }.count

if ready == notReady {
    print("🎊 you are ready for Swift Package Manager")
} else {
    print("Sorry 😢 - ✅ \(ready) | ❌ \(notReady)")
    print("Help to improve SPM capablility by opening an issue or contribute via PR")
}

//for pod in pods {
//    print(pod.format())
//}



