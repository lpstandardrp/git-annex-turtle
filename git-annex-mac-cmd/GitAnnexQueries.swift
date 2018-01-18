//
//  GitAnnexQueries.swift
//  git-annex-finder
//
//  Created by Andrew Ringler on 12/31/17.
//  Copyright © 2017 Andrew Ringler. All rights reserved.
//

import Foundation

class GitAnnexQueries {
    // TODO one queue per repository
    static let gitAnnexQueryQueue = DispatchQueue(label: "com.andrewringler.git-annex-mac.shellcommandqueue")
    
    // https://gist.github.com/brennanMKE/a0a2ee6aa5a2e2e66297c580c4df0d66
    private class func directoryExistsAtPath(_ path: String) -> Bool {
        var isDirectory = ObjCBool(true)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /* Adapted from https://stackoverflow.com/questions/29514738/get-terminal-output-after-a-command-swift
     * with fixes for leaving dangling open file descriptors from here:
     * http://www.cocoabuilder.com/archive/cocoa/289471-file-descriptors-not-freed-up-without-closefile-call.html
    */
    private class func runCommand(workingDirectory: String, cmd : String, args : String...) -> (output: [String], error: [String], status: Int32) {
        // protect access to git annex, I don't think you can query it
        // too heavily concurrently on the same repo, and plus I was getting
        // too many open files warnings
        // when I let all my processes access this method
        
        // ref on threading https://medium.com/@irinaernst/swift-3-0-concurrent-programming-with-gcd-5ee51e89091f
        var ret: (output: [String], error: [String], status: Int32) = ([""], ["ERROR: task did not run"], -1)
        
//        gitAnnexQueryQueue.sync {
            var output : [String] = []
            var error : [String] = []
            
            /* check for a valid working directory now, because Process will not let us catch
             * the exception thrown if the directory is invalid */
            if !directoryExistsAtPath(workingDirectory) {
                NSLog("Invalid working directory '%@'", workingDirectory)
                return ret
            }

            let task = Process()
            task.launchPath = cmd
            task.currentDirectoryPath = workingDirectory
            task.arguments = args

            // TODO wrap commands in a shell (that is likely to exist) to avoid uncatchable errors
            // IE if workingDirectory does not exist we cannot catch that error
            // uncatchable runtime exceptions
            // see https://stackoverflow.com/questions/34420706/how-to-catch-error-when-setting-launchpath-in-nstask
//            let task = Process()
//            task.launchPath = "/bin/bash"
//            task.currentDirectoryPath = workingDirectory
//            var bashCmd :[String] = [cmd]
//            for arg: String in args {
//                bashCmd.append(arg)
//            }
//            let bashCmdString: String = "cd '" + workingDirectory + "';" +
//            let bashArgs :[String] = ["-c", bashCmd.joined(separator: " ")]
//            task.arguments = bashArgs
//            NSLog("How does this look? %@", bashArgs)

            let outpipe = Pipe()
            task.standardOutput = outpipe
            let errpipe = Pipe()
            task.standardError = errpipe
            
            task.launch()
            
            let outputFileHandle = outpipe.fileHandleForReading
            let outdata = outputFileHandle.readDataToEndOfFile()
            if var string = String(data: outdata, encoding: .utf8) {
                string = string.trimmingCharacters(in: .newlines)
                output = string.components(separatedBy: "\n")
            }
            // NOTE see http://www.cocoabuilder.com/archive/cocoa/289471-file-descriptors-not-freed-up-without-closefile-call.html
            // i was running out of file descriptors without this
            // even though the documentation clearly says it is not needed
            outputFileHandle.closeFile()
            
            let errFileHandle = errpipe.fileHandleForReading
            let errdata = errFileHandle.readDataToEndOfFile()
            if var string = String(data: errdata, encoding: .utf8) {
                string = string.trimmingCharacters(in: .newlines)
                error = string.components(separatedBy: "\n")
            }
            // NOTE see http://www.cocoabuilder.com/archive/cocoa/289471-file-descriptors-not-freed-up-without-closefile-call.html
            // i was running out of file descriptors without this
            // even though the documentation clearly says it is not needed
            errFileHandle.closeFile()
            
            task.waitUntilExit()
            let status = task.terminationStatus
            
            ret = (output, error, status)
//        }
        
        return ret
    }

    class func gitAnnexCommand(for url: URL, in workingDirectory: String, cmd: GitAnnexCommand) -> (success: Bool, error: [String], output: [String], commandRun: String) {
        if let path = PathUtils.path(for: url) {
            let (output, error, status) = runCommand(workingDirectory: workingDirectory, cmd: "/Applications/git-annex.app/Contents/MacOS/git-annex", args: cmd.cmdString, path)
            let commandRun = "git-annex " + cmd.cmdString + " \"" + path + "\""

            if status != 0 {
                NSLog(commandRun)
                NSLog("status: %@", String(status))
                NSLog("output: %@", output)
                NSLog("error: %@", error)
            }
            
            return (status == 0, error, output, commandRun)
        } else {
            NSLog("unable to get path from URL '%@'", url.absoluteString)
        }
        
        return (false, ["git-annex-turtle: unknown error"], ["Command '" + cmd.cmdString + "'did not run. Unable to retrieve file path for URL='" + url.absoluteString + "'"], "n/a")
    }
    class func gitCommand(for url: URL, in workingDirectory: String, cmd: GitCommand) -> (success: Bool, error: [String], output: [String], commandRun: String) {
        if let path = PathUtils.path(for: url) {
            let (output, error, status) = runCommand(workingDirectory: workingDirectory, cmd: "/Applications/git-annex.app/Contents/MacOS/git", args: cmd.cmdString, path)
            let commandRun = "git " + cmd.cmdString + "\"" + path + "\""
            
            if status != 0 {
                NSLog(commandRun)
                NSLog("status: %@", String(status))
                NSLog("output: %@", output)
                NSLog("error: %@", error)
            }
            return (status == 0, error, output, commandRun)
        } else {
            NSLog("unable to get path from URL '%@'", url.absoluteString)
        }

        return (false, ["git-annex-turtle: unknown error"], ["Command '" + cmd.cmdString + "'did not run. Unable to retrieve file path for URL='" + url.absoluteString + "'"], "n/a")
    }
    class func gitGitAnnexUUID(in workingDirectory: String) -> UUID? {
        // is this folder even a directory?
        if !directoryExistsAtPath(workingDirectory) {
            NSLog("Not a valid git-annex folder, nor even a directory '%@'", workingDirectory)
            return nil
        }
        
        let (output, error, status) = runCommand(workingDirectory: workingDirectory, cmd: "/Applications/git-annex.app/Contents/MacOS/git", args: "config", GitConfigs.AnnexUUID.name)
        
        if status == 0, output.count == 1 {
            for uuidString in output {
                if let uuid = UUID(uuidString: uuidString) {
                    return uuid
                }
                break
            }
        }

        if status != 0 {
            NSLog("git config %@",GitConfigs.AnnexUUID.name)
            NSLog("status: %@", String(status))
            NSLog("output: %@", output)
            NSLog("error: %@", error)
        }
        return nil
    }
    class func gitAnnexPathInfo(for url: URL, in workingDirectory: String, calculateLackingCopiesForDirs: Bool) -> Status {
        if let path :String = PathUtils.path(for: url) {
            let (output, error, status) = runCommand(workingDirectory: workingDirectory, cmd: "/Applications/git-annex.app/Contents/MacOS/git-annex", args: "--json", "--fast", "info", path)
            
            if status != 0 {
                NSLog("gitAnnexPathInfo for url='\(url)' in='\(workingDirectory)'")
                NSLog("status: %@", String(status))
                NSLog("output: %@", output)
                NSLog("error: %@", error)
            }
            
            // if command didnt return an error, parse the JSON
            // https://stackoverflow.com/questions/25621120/simple-and-clean-way-to-convert-json-string-to-object-in-swift
            if(status == 0){
                do {
                    var data: Data = (output.first as! NSString).data(using: String.Encoding.utf8.rawValue)!
                    var json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: 0))
                    
                    if let dictionary = json as? [String: Any] {
                        let success = dictionary[GitAnnexJSON.success.rawValue]
                        let present = dictionary[GitAnnexJSON.present.rawValue]
                        let file = dictionary[GitAnnexJSON.file.rawValue]
                        let directory = dictionary[GitAnnexJSON.directory.rawValue]
                        let localAnnexKeys = dictionary[GitAnnexJSON.localAnnexKeys.rawValue]
                        let annexedFilesInWorkingTree = dictionary[GitAnnexJSON.annexedFilesInWorkingTree.rawValue]
                        let command = dictionary[GitAnnexJSON.command.rawValue]
                        
                        // a file in the annex that is present
                        if success != nil && (success as! Bool) == true
                            && present != nil && (present as! Bool) == true {
                            // get number of copies
                            if let lackingCopies = GitAnnexQueries.gitAnnexLackingCopies(for: url, in: workingDirectory, skipDirs: true) {
                                return lackingCopies ? Status.presentNotNumcopies : Status.present
                            }
                            return Status.present
                        }
                        
                        // a file in the annex that is not present
                        if success != nil && (success as! Bool) == true
                            && present != nil && (present as! Bool) == false {
                            // get number of copies
                            if let lackingCopies = GitAnnexQueries.gitAnnexLackingCopies(for: url, in: workingDirectory, skipDirs: true) {
                                return lackingCopies ? Status.absentNotNumcopies : Status.absent
                            }
                            return Status.absent
                        }
                        
                        // a directory in the annex who has all the content
                        // of all his containing files recursively
                        if success != nil && (success as! Bool) == true
                            && localAnnexKeys != nil && annexedFilesInWorkingTree != nil
                            && (annexedFilesInWorkingTree as! Int) == (localAnnexKeys as! Int) {
                            // get number of copies
                            if calculateLackingCopiesForDirs, let lackingCopies = GitAnnexQueries.gitAnnexLackingCopies(for: url, in: workingDirectory, skipDirs: false) {
                                return lackingCopies ? Status.presentNotNumcopies : Status.present
                            }
                            return Status.presentCalculatingNumcopies
                        }
                        
                        // a directory in the annex who is missing all
                        // content from some all of his containing files recursively
                        if success != nil && (success as! Bool) == true
                            && localAnnexKeys != nil && annexedFilesInWorkingTree != nil
                            && (localAnnexKeys as! Int) < (annexedFilesInWorkingTree as! Int)
                            && (localAnnexKeys as! Int) == 0
                        {
                            if calculateLackingCopiesForDirs, let lackingCopies = GitAnnexQueries.gitAnnexLackingCopies(for: url, in: workingDirectory, skipDirs: false ) {
                                return lackingCopies ? Status.absentNotNumcopies : Status.absent
                            }
                            return Status.absentCalculatingNumcopies
                        }
                        
                        // a directory in the annex who is missing some
                        // content from some of his containing files recursively
                        if success != nil && (success as! Bool) == true
                            && localAnnexKeys != nil && annexedFilesInWorkingTree != nil
                            && (localAnnexKeys as! Int) < (annexedFilesInWorkingTree as! Int)
                            && (localAnnexKeys as! Int) > 0
                        {
                            // TODO different icons than absent?
                            if calculateLackingCopiesForDirs, let lackingCopies = GitAnnexQueries.gitAnnexLackingCopies(for: url, in: workingDirectory, skipDirs: true) {
                                return lackingCopies ? Status.absentNotNumcopies : Status.absent
                            }
                            return Status.absentCalculatingNumcopies
                        }
                    }
                } catch {
                    NSLog("unable to parse JSON: '", output, "'")
                }
            }
            return Status.unknown
        } else {
            NSLog("could not get path for URL '%@'", url.absoluteString)
        }
        return Status.unknown
    }
    
//    class func gitAnnexNumberOfCopies(for url: URL, in workingDirectory: String) -> Int? {
//        if let path = PathUtils.path(for: url) {
//            var isDirectory = ObjCBool(true)
//            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
//            if exists && isDirectory.boolValue {
//                // TODO make meaningful queries on number of copies for directories?
//                // skip directories
//                return nil
//            }
//
//            let (output, error, status) = runCommand(workingDirectory: workingDirectory, cmd: "/Applications/git-annex.app/Contents/MacOS/git-annex", args: "--json", "--fast", "whereis", path)
//
//            // if command didnt return an error, parse the JSON
//            // https://stackoverflow.com/questions/25621120/simple-and-clean-way-to-convert-json-string-to-object-in-swift
//            if(status == 0){
//                do {
//                    let data: Data = (output.first as! NSString).data(using: String.Encoding.utf8.rawValue)!
//                    let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: 0))
//
//                    if let dictionary = json as? [String: Any] {
//                        let success = dictionary[GitAnnexJSON.success.rawValue]
//                        let whereis = dictionary[GitAnnexJSON.whereis.rawValue] as? [[String: Any]]
//
//                        // return number of copies
//                        if success != nil && whereis != nil {
//                            return whereis?.count ?? nil
//                        } else {
//                            NSLog("issue getting data from JSON: '\(dictionary)'")
//                        }
//                    }
//                } catch {
//                    NSLog("unable to parse JSON: '\(output)' for url='\(url)' workingdir='\(workingDirectory)'")
//                }
//            } else {
//                NSLog("gitAnnexNumberOfCopies")
//                NSLog("status: %@", String(status))
//                NSLog("output: %@", output)
//                NSLog("error: %@", error)
//                return nil
//            }
//        } else {
//            NSLog("could not get path for URL \(url)")
//        }
//        return nil
//    }
    
    /* git annex find --lackingcopies=1 --json
     * returns a line for every file that is lacking 1 or more copies
     * calling this on directories causes git-annex to query each child file recursively
     * this can be slow, so pass skipDirs=true when this needs to happen quickly
     */
    class func gitAnnexLackingCopies(for url: URL, in workingDirectory: String, skipDirs: Bool) -> Bool? {
        if let path = PathUtils.path(for: url) {
            if skipDirs {
                var isDirectory = ObjCBool(true)
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                if exists && isDirectory.boolValue {
                    return nil
                }
            }
            
            let (output, error, status) = runCommand(workingDirectory: workingDirectory, cmd: "/Applications/git-annex.app/Contents/MacOS/git-annex", args: "--json", "--fast", "--lackingcopies=1", "find", path)
            
            // if command didnt return an error, count the lines returned
            if(status == 0){
                if let firstLine = output.first {
                    return !firstLine.isEmpty
                }
                return false
            } else {
                NSLog("gitAnnexLackingCopies")
                NSLog("status: %@", String(status))
                NSLog("output: %@", output)
                NSLog("error: %@", error)
                return nil
            }
        } else {
            NSLog("could not get path for URL \(url)")
        }
        return nil
    }
}
