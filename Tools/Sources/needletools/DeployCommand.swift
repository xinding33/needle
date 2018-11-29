//
//  Copyright (c) 2018. Uber Technologies
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Utility

/// The command to deploy a new version of Needle to all distribution
/// channels.
class DeployCommand: AbstractCommand {

    /// Initializer.
    ///
    /// - parameter parser: The argument parser to use.
    init(parser: ArgumentParser) {
        super.init(name: "deploy", overview: "Create and deploy a new Needle release.", parser: parser)
    }

    /// Setup the arguments using the given parser.
    ///
    /// - parameter parser: The argument parser to use.
    override func setupArguments(with parser: ArgumentParser) {
        super.setupArguments(with: parser)

        versionNumberString = parser.add(positional: "versionNumberString", kind: String.self, usage: "The version number string.")
    }

    /// Execute the command.
    ///
    /// - parameter arguments: The command line arguments to execute the
    /// command with.
    override func execute(with arguments: ArgumentParser.Result) {
        super.execute(with: arguments)

        if let versionNumberString = arguments.get(self.versionNumberString) {
            do {
                let newVersion = try Version.from(string: versionNumberString)
                if assert(newVersion: newVersion) {
                    let isDryRun = self.isDryRun(with: arguments)
                    checkoutMaster(isDryRun: isDryRun)
                    archieveGenerator(isDryRun: isDryRun)
                    pushBinary(with: newVersion, isDryRun: isDryRun)
                    createTag(with: newVersion, isDryRun: isDryRun)
                    updateVersion(to: newVersion, isDryRun: isDryRun)
                    print("Finished deploying \(newVersion.stringValue)")
                }
            } catch {
                fatalError("Invalid version string format. The version must be in the format of `major.minor.patch`, where all components are numbers only.")
            }
        } else {
            fatalError("Version number string must be specified.")
        }
    }

    // MARK: - Private

    private var versionNumberString: PositionalArgument<String>!

    private func assert(newVersion: Version) -> Bool {
        print("Are you sure you want to deploy a new version of Needle with the version \(newVersion.stringValue)? [y/n]")

        let response = readLine(strippingNewline: true)?.lowercased() ?? ""
        let shouldContinue = response.first == "y"

        if shouldContinue {
            do  {
                let currentVersion = try Version.currentVersion()
                if newVersion <= currentVersion {
                    fatalError("New version must be greater than current version \(currentVersion.stringValue)")
                }
            } catch {
                fatalError("Failed to parse current version.")
            }
        }

        return shouldContinue
    }

    private func checkoutMaster(isDryRun: Bool) {
        print("Switching to `master` branch...")

        do  {
            try GitUtilities.checkoutMaster(isDryRun: isDryRun)
        } catch {
            fatalError("\(error)")
        }
    }

    private func archieveGenerator(isDryRun: Bool) {
        print("Archiving generator binary...")

        let buildResult = CompilerUtilities.buildGenerator()
        if !buildResult.status {
            fatalError(buildResult.error)
        }

        let moveResult = ProcessUtilities.move(Paths.generatorArchieve, to: Paths.generatorBin, isDryRun: isDryRun)
        if !moveResult.status {
            fatalError(moveResult.error)
        }
    }

    private func pushBinary(with version: Version, isDryRun: Bool) {
        print("Pushing new binary (\(Paths.generatorBinary)) to Git remote master branch...")

        do {
            try GitUtilities.push(file: Paths.generatorBinary, withMessage: "\(version.stringValue) generator binary", isDryRun: isDryRun)
        } catch {
            fatalError("\(error)")
        }
    }

    private func createTag(with version: Version, isDryRun: Bool) {
        print("Creating and pushing a new tag \(version.stringValue)...")

        do {
            try GitUtilities.createTag(withVersion: version.stringValue, isDryRun: isDryRun)
        } catch {
            fatalError("\(error)")
        }
    }

    private func updateVersion(to newVersion: Version, isDryRun: Bool) {
        print("Recording new version number \(newVersion.stringValue)...")

        do {
            try newVersion.setAsCurrent(isDryRun: isDryRun)
            try GitUtilities.push(file: Paths.versionFile, withMessage: "Update version", isDryRun: isDryRun)
        } catch {
            fatalError("Failed to update version file to \(newVersion.stringValue)")
        }
    }
}