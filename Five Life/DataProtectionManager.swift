import Foundation

enum DataProtectionManager {
    static func configureDefaultFileProtection() {
        let fileManager = FileManager.default
        let directories = protectedDirectories(fileManager: fileManager)

        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
                try fileManager.setAttributes([.protectionKey: FileProtectionType.complete],
                                              ofItemAtPath: directory.path)
            } catch {
                // Do not block app startup if iOS refuses to change protection on a
                // system-managed directory. Individual sensitive writes still request
                // complete file protection where possible.
            }
        }
    }

    private static func protectedDirectories(fileManager: FileManager) -> [URL] {
        var directories: [URL] = []
        if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first {
            directories.append(applicationSupport)
        }
        if let documents = fileManager.urls(for: .documentDirectory,
                                            in: .userDomainMask).first {
            directories.append(documents)
        }
        return directories
    }
}
