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
                setenv("VERTEX_PROXY_PASSWORD_FILE", path, 1)
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
