import Darwin
import Foundation
import VertexKit

enum ProxyPasswordStorageTests {
    static func runAll() {
        TestRunner.run("ProxyPassword: file 0600 selezionato dalla preferenza") {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: PrefKey.proxyPasswordInFile)
            let workspace = try IntegrationWorkspace()
            defer {
                workspace.cleanup()
                if let previous {
                    defaults.set(previous, forKey: PrefKey.proxyPasswordInFile)
                } else {
                    defaults.removeObject(forKey: PrefKey.proxyPasswordInFile)
                }
                unsetenv("VERTEX_PROXY_PASSWORD_FILE")
            }

            let file = workspace.root.appendingPathComponent("proxy-password")
            file.path.withCString { path in
                _ = setenv("VERTEX_PROXY_PASSWORD_FILE", path, 1)
            }
            defaults.set(true, forKey: PrefKey.proxyPasswordInFile)

            try TestRunner.assertTrue(ProxyPasswordStore.write("s3cret"))
            switch ProxyPasswordStore.read() {
            case .success(let value):
                try TestRunner.assertEqual(value, "s3cret")
            case .failure:
                try TestRunner.assertTrue(false, "La lettura dal file deve riuscire")
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            try TestRunner.assertEqual(
                permissions & 0o777,
                0o600,
                "Il file della password deve essere leggibile solo dal proprietario"
            )

            try TestRunner.assertTrue(ProxyPasswordStore.write(""))
            try TestRunner.assertFalse(
                FileManager.default.fileExists(atPath: file.path),
                "Una password vuota deve rimuovere il file"
            )
        }

        TestRunner.run("ProxyPassword: file esistente troppo permissivo riportato a 0600 alla lettura") {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: PrefKey.proxyPasswordInFile)
            let workspace = try IntegrationWorkspace()
            defer {
                workspace.cleanup()
                if let previous {
                    defaults.set(previous, forKey: PrefKey.proxyPasswordInFile)
                } else {
                    defaults.removeObject(forKey: PrefKey.proxyPasswordInFile)
                }
                unsetenv("VERTEX_PROXY_PASSWORD_FILE")
            }

            let file = workspace.root.appendingPathComponent("proxy-password")
            file.path.withCString { path in
                _ = setenv("VERTEX_PROXY_PASSWORD_FILE", path, 1)
            }
            defaults.set(true, forKey: PrefKey.proxyPasswordInFile)

            try Data("legacy".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

            switch ProxyPasswordStore.read() {
            case .success(let value):
                try TestRunner.assertEqual(value, "legacy")
            case .failure:
                try TestRunner.assertTrue(false, "La lettura dal file deve riuscire")
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            try TestRunner.assertEqual(
                permissions & 0o777,
                0o600,
                "Un file leggibile da gruppo o altri deve essere ristretto a 0600"
            )
        }

        TestRunner.run("ProxyPassword: scrittura senza residui temporanei e con cartella 0700") {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: PrefKey.proxyPasswordInFile)
            let workspace = try IntegrationWorkspace()
            defer {
                workspace.cleanup()
                if let previous {
                    defaults.set(previous, forKey: PrefKey.proxyPasswordInFile)
                } else {
                    defaults.removeObject(forKey: PrefKey.proxyPasswordInFile)
                }
                unsetenv("VERTEX_PROXY_PASSWORD_FILE")
            }

            let folder = workspace.root.appendingPathComponent("existing-support")
            let file = folder.appendingPathComponent("proxy-password")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            file.path.withCString { path in
                _ = setenv("VERTEX_PROXY_PASSWORD_FILE", path, 1)
            }
            defaults.set(true, forKey: PrefKey.proxyPasswordInFile)

            try TestRunner.assertTrue(ProxyPasswordStore.write("first"))
            try TestRunner.assertTrue(ProxyPasswordStore.write("second"))

            let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            try TestRunner.assertEqual(entries, ["proxy-password"], "Nessun file temporaneo deve restare")

            let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            try TestRunner.assertEqual(
                permissions & 0o777,
                0o700,
                "Anche una cartella preesistente deve essere ristretta a 0700"
            )
            switch ProxyPasswordStore.read() {
            case .success(let value):
                try TestRunner.assertEqual(value, "second")
            case .failure:
                try TestRunner.assertTrue(false, "La lettura dal file deve riuscire")
            }
        }

        TestRunner.run("ProxyPassword: un symlink non viene letto né chmodato") {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: PrefKey.proxyPasswordInFile)
            let workspace = try IntegrationWorkspace()
            defer {
                workspace.cleanup()
                if let previous {
                    defaults.set(previous, forKey: PrefKey.proxyPasswordInFile)
                } else {
                    defaults.removeObject(forKey: PrefKey.proxyPasswordInFile)
                }
                unsetenv("VERTEX_PROXY_PASSWORD_FILE")
            }

            let target = workspace.root.appendingPathComponent("target.txt")
            let link = workspace.root.appendingPathComponent("proxy-password")
            try Data("not-a-password".utf8).write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            link.path.withCString { path in
                _ = setenv("VERTEX_PROXY_PASSWORD_FILE", path, 1)
            }
            defaults.set(true, forKey: PrefKey.proxyPasswordInFile)

            switch ProxyPasswordStore.read() {
            case .success(let value):
                try TestRunner.assertEqual(value, nil, "Un symlink non è un file di password")
            case .failure:
                try TestRunner.assertTrue(false, "Un symlink deve essere ignorato, non letto")
            }

            let targetAttributes = try FileManager.default.attributesOfItem(atPath: target.path)
            let targetPermissions = (targetAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            try TestRunner.assertEqual(
                targetPermissions & 0o777,
                0o644,
                "Il file puntato non deve essere chmodato"
            )

            try TestRunner.assertTrue(ProxyPasswordStore.write("replacement"))
            let replaced = try FileManager.default.attributesOfItem(atPath: link.path)
            try TestRunner.assertEqual(replaced[.type] as? FileAttributeType, .typeRegular)
            let replacedPermissions = (replaced[.posixPermissions] as? NSNumber)?.intValue ?? 0
            try TestRunner.assertEqual(replacedPermissions & 0o777, 0o600)
            try TestRunner.assertEqual(
                try String(contentsOf: target, encoding: .utf8),
                "not-a-password",
                "Il file puntato deve restare intatto"
            )
        }

        TestRunner.run("ProxyPassword: Portachiavi disattivato nel runner") {
            let defaults = UserDefaults.standard
            let previous = defaults.object(forKey: PrefKey.proxyPasswordInFile)
            defer {
                if let previous {
                    defaults.set(previous, forKey: PrefKey.proxyPasswordInFile)
                } else {
                    defaults.removeObject(forKey: PrefKey.proxyPasswordInFile)
                }
            }
            defaults.set(false, forKey: PrefKey.proxyPasswordInFile)

            switch ProxyPasswordStore.read() {
            case .failure(.disabled):
                break
            default:
                try TestRunner.assertTrue(
                    false,
                    "Con il Portachiavi disattivato la lettura deve riportare .disabled"
                )
            }
        }
    }
}
