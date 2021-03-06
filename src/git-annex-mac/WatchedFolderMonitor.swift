//
//  WatchedFolderMonitor.swift
//  git-annex-turtle
//
//  Created by Andrew Ringler on 1/18/18.
//  Copyright © 2018 Andrew Ringler. All rights reserved.
//

import Foundation

class WatchedFolderMonitor: StoppableService {
    public let watchedFolder: WatchedFolder
    
    private let updateChecker: RunNowOrAgain1<Double>
    private var fileMonitor: Witness?
    
    init(watchedFolder: WatchedFolder, app: WatchGitAndFinderForUpdates) {
        self.watchedFolder = watchedFolder

        updateChecker = RunNowOrAgain1({ (secondsOld: Double) in
            app.checkForGitAnnexUpdates(in: watchedFolder, secondsOld: secondsOld)
        })
        
        super.init()
        
        let watchPath = "\(watchedFolder.pathString)"
        TurtleLog.debug("Setting up file system watch for '\(watchPath)'")
        
        fileMonitor = Witness(paths: [watchPath], flags: .FileEvents, latency: 0.1) { events
            in
            var shouldUpdate = false
            for event in events {
                if event.path.contains(".git/annex/misctmp") ||
                    event.path.contains(".git/annex/mergedrefs") ||
                    event.path.contains(".git/annex/tmp")
                {
                    // ignore, these can change just by read-only querying git-annex
                } else {
                    shouldUpdate = true // there is at least one change event we care about
                    break
                }
            }
            if shouldUpdate {
                self.updateChecker.runTaskAgain(p1: 0 /* seconds old */)
            }
        }
    }
    
    public func doUpdates() {
        updateChecker.runTaskAgain(p1: 0 /* seconds old */)
    }
    
    override public func stop() {
        fileMonitor = nil
        updateChecker.stop()
        super.stop()
    }
}
