import AppKit
import CTorrent
import Foundation

private final class SettingsApplyOutcomeBox: @unchecked Sendable {
    var proxySucceeded = false
    var networkSucceeded = false
    var queueSucceeded = false
    var downloadPathSucceeded = false
    var firstErrorMessage = ""
}

extension TorrentEngine {
    /// Coalesces the edits of a settings field: applying on every keystroke
    /// rebinds the listening port (and resets the port mapping) for partial
    /// values like `6` or `68`. Closing the sheet still flushes immediately.
    func applySettingsSoon() {
        settingsApplyTask?.cancel()
        settingsApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.settingsApplyTask = nil
            self.applySettings()
        }
    }

    /// Cancels a pending debounced update and applies the current preferences
    /// immediately.
    func applySettingsNow() {
        settingsApplyTask?.cancel()
        settingsApplyTask = nil
        applySettings()
    }

    func applySettings() {
        guard !isShuttingDown, !isRestartingSession, hasSession else { return }

        let fallback = lastAppliedConfiguration
        var proxyFailCloseReason: String?
        let configuration: SessionConfiguration
        if let configurationOverride {
            configuration = configurationOverride
            if configuration.proxyEnabled {
                let trimmedHost = configuration.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedHost.isEmpty {
                    proxyFailCloseReason = "Host proxy non valido"
                    showToast(L("Host proxy non valido"), kind: .error)
                } else if !Preferences.isValidPort(Int(configuration.proxyPort)) {
                    proxyFailCloseReason = "Porta proxy fuori intervallo (1–65535)."
                    showToast(
                        L("Porta proxy non valida"),
                        kind: .error,
                        detail: L("Inserisci un valore tra 1 e 65535.")
                    )
                }
            }
        } else {
            let defaults = Preferences.userDefaults

            let rawPort = defaults.integer(forKey: PrefKey.listenPort)
            let port: Int32
            if Preferences.isValidPort(rawPort) {
                port = Int32(rawPort)
            } else {
                showToast(
                    L("Porta non valida"),
                    kind: .error,
                    detail: L("Inserisci un valore tra 1 e 65535.")
                )
                port = fallback?.port ?? Int32(PrefDefault.listenPort)
            }

            let rawDownloadKB = defaults.integer(forKey: PrefKey.downloadLimitKB)
            let rawUploadKB = defaults.integer(forKey: PrefKey.uploadLimitKB)
            let validDownloadKB = Preferences.isValidLimitKB(rawDownloadKB)
            let validUploadKB = Preferences.isValidLimitKB(rawUploadKB)
            if !validDownloadKB || !validUploadKB {
                showToast(
                    L("Limite non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 o un valore positivo entro il massimo consentito.")
                )
            }
            let downloadLimit =
                validDownloadKB
                ? Preferences.limitBytes(fromKB: rawDownloadKB)
                : (fallback?.downloadLimit ?? Preferences.limitBytes(fromKB: PrefDefault.downloadLimitKB))
            let uploadLimit =
                validUploadKB
                ? Preferences.limitBytes(fromKB: rawUploadKB)
                : (fallback?.uploadLimit ?? Preferences.limitBytes(fromKB: PrefDefault.uploadLimitKB))

            let rawMaxActive = defaults.integer(forKey: PrefKey.maxActiveTorrents)
            let maxActive: Int32
            if Preferences.isValidActiveLimit(rawMaxActive) {
                maxActive = Int32(rawMaxActive)
            } else {
                showToast(
                    L("Numero di torrent attivi non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 (illimitato) o un valore tra 1 e 1000.")
                )
                maxActive = fallback?.maxActive ?? Int32(PrefDefault.maxActiveTorrents)
            }

            let rawSeedRatio = defaults.double(forKey: PrefKey.seedRatioLimit)
            let seedRatioLimit: Double
            if Preferences.isValidSeedRatio(rawSeedRatio) {
                seedRatioLimit = Preferences.clampedSeedRatio(rawSeedRatio)
            } else {
                showToast(
                    L("Limite rapporto non valido"),
                    kind: .error,
                    detail: L("Inserisci 0 (illimitato) o un valore positivo fino a 100.")
                )
                seedRatioLimit = fallback?.seedRatioLimit ?? PrefDefault.seedRatioLimit
            }

            let rawBind = (defaults.string(forKey: PrefKey.bindAddress) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let bindAddress: String
            if rawBind.isEmpty {
                bindAddress = ""
            } else if Preferences.isValidIPv4(rawBind) {
                bindAddress = rawBind
            } else {
                showToast(L("Parametri non validi."), kind: .error)
                bindAddress = fallback?.bindAddress ?? PrefDefault.bindAddress
            }

            let proxyEnabled = defaults.bool(forKey: PrefKey.proxyEnabled)
            let rawProxyHost = (defaults.string(forKey: PrefKey.proxyHost) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rawProxyPort = defaults.integer(forKey: PrefKey.proxyPort)
            if proxyEnabled {
                if rawProxyHost.isEmpty {
                    proxyFailCloseReason = "Host proxy non valido"
                    showToast(L("Host proxy non valido"), kind: .error)
                } else if !Preferences.isValidPort(rawProxyPort) {
                    proxyFailCloseReason = "Porta proxy fuori intervallo (1–65535)."
                    showToast(
                        L("Porta proxy non valida"),
                        kind: .error,
                        detail: L("Inserisci un valore tra 1 e 65535.")
                    )
                }
            }
            let proxyHost = proxyEnabled ? rawProxyHost : (rawProxyHost.isEmpty ? PrefDefault.proxyHost : rawProxyHost)
            let proxyPort: Int32
            if Preferences.isValidPort(rawProxyPort) {
                proxyPort = Int32(rawProxyPort)
            } else if proxyEnabled {
                proxyPort = Int32(clamping: rawProxyPort)
            } else {
                proxyPort = Int32(PrefDefault.proxyPort)
            }

            let rawDownload = defaults.string(forKey: PrefKey.downloadPath)
            let resolvedDownload: String
            if rawDownload == cachedRawDownloadPath, let cachedResolvedDownloadPath {
                resolvedDownload = cachedResolvedDownloadPath
            } else {
                resolvedDownload = Preferences.resolvedDownloadPath(rawDownload)
                cachedRawDownloadPath = rawDownload
                cachedResolvedDownloadPath = resolvedDownload
            }

            configuration = SessionConfiguration(
                downloadPath: resolvedDownload,
                resumePath: Preferences.resumeDirectory.path,
                port: port,
                maxActive: maxActive,
                downloadLimit: downloadLimit,
                uploadLimit: uploadLimit,
                seedRatioLimit: seedRatioLimit,
                dht: defaults.bool(forKey: PrefKey.dhtEnabled),
                pex: defaults.bool(forKey: PrefKey.pexEnabled),
                lsd: defaults.bool(forKey: PrefKey.lsdEnabled),
                upnp: defaults.bool(forKey: PrefKey.upnpEnabled),
                bindAddress: bindAddress,
                proxyEnabled: proxyEnabled,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUser: defaults.string(forKey: PrefKey.proxyUser) ?? "",
                proxyPassword: proxyEnabled ? Preferences.proxyPassword : ""
            )
        }

        if configuration.pex != sessionPexEnabled, proxyFailCloseReason == nil {
            restartSessionForPeerExchange(configuration: configuration, oldPex: sessionPexEnabled)
            return
        }

        // Serialize settings diffs: lastAppliedConfiguration updates only once
        // the actor finishes, so a second edit while one is in flight must re-run
        // afterwards instead of comparing against the stale baseline.
        if isApplyingSettings {
            needsSettingsReapply = true
            return
        }

        // Apply only the parts that changed since the last successful apply.
        // This keeps a debounced settings edit from touching the filesystem or
        // rebinding the listening port when the value is unchanged.
        let previous = lastAppliedConfiguration
        let previousFailClose = lastAppliedProxyFailCloseReason
        if configuration == previous, proxyFailCloseReason == previousFailClose { return }

        let downloadPathChanged: Bool
        let networkChanged: Bool
        let queueChanged: Bool
        let proxyChanged: Bool
        if let previous {
            downloadPathChanged = previous.downloadPath != configuration.downloadPath
            queueChanged = previous.maxActive != configuration.maxActive
            networkChanged =
                previous.port != configuration.port
                || previous.downloadLimit != configuration.downloadLimit
                || previous.uploadLimit != configuration.uploadLimit
                || previous.dht != configuration.dht
                || previous.upnp != configuration.upnp
                || previous.lsd != configuration.lsd
                || previous.bindAddress != configuration.bindAddress
            proxyChanged =
                proxyFailCloseReason != previousFailClose
                || previous.proxyEnabled != configuration.proxyEnabled
                || previous.proxyHost != configuration.proxyHost
                || previous.proxyPort != configuration.proxyPort
                || previous.proxyUser != configuration.proxyUser
                || previous.proxyPassword != configuration.proxyPassword
        } else {
            downloadPathChanged = true
            networkChanged = true
            queueChanged = true
            proxyChanged = true
        }

        guard downloadPathChanged || networkChanged || queueChanged || proxyChanged else {
            lastAppliedConfiguration = configuration
            lastAppliedProxyFailCloseReason = proxyFailCloseReason
            if configuration.seedRatioLimit > 0 {
                poll()
            }
            return
        }

        if proxyChanged || networkChanged {
            proxyProbeGeneration += 1
            isProxyProbeInFlight = false
            proxyHealthError = nil
            proxyCheckTick = 9
        }

        let applyGeneration = sessionGeneration
        let failCloseReason = proxyFailCloseReason
        let outcomeBox = SettingsApplyOutcomeBox()
        isApplyingSettings = true
        needsSettingsReapply = false
        let queued = enqueueSessionOperation(
            errorTitle: L("Impostazioni non applicate"),
            operation: { session in
                var firstFailureCode: Int32 = 0
                func recordFailure(_ code: Int32) {
                    guard firstFailureCode == 0 else { return }
                    firstFailureCode = code
                    if let pointer = vt_last_error(session) {
                        outcomeBox.firstErrorMessage = String(cString: pointer)
                        vt_free_string(pointer)
                    }
                }

                // Security-critical proxy posture runs FIRST so an unwritable or
                // unmounted download folder can never block fail-closed / SOCKS5.
                if let failReason = failCloseReason {
                    failReason.withCString { reasonPointer in
                        vt_fail_close_proxy(session, reasonPointer)
                    }
                    outcomeBox.proxySucceeded = true
                } else if proxyChanged {
                    let proxyResult = configuration.proxyHost.withCString { hostPointer in
                        configuration.proxyUser.withCString { userPointer in
                            configuration.proxyPassword.withCString { passPointer in
                                vt_apply_proxy_settings(
                                    session,
                                    configuration.proxyEnabled ? 1 : 0,
                                    hostPointer,
                                    configuration.proxyPort,
                                    userPointer,
                                    passPointer
                                )
                            }
                        }
                    }
                    if proxyResult == 0 {
                        outcomeBox.proxySucceeded = true
                    } else {
                        recordFailure(proxyResult)
                    }
                } else {
                    outcomeBox.proxySucceeded = true
                }

                if networkChanged {
                    let netResult = configuration.bindAddress.withCString { bindAddress in
                        vt_apply_settings_ex(
                            session,
                            configuration.port,
                            configuration.downloadLimit,
                            configuration.uploadLimit,
                            configuration.dht ? 1 : 0,
                            configuration.upnp ? 1 : 0,
                            configuration.lsd ? 1 : 0,
                            bindAddress
                        )
                    }
                    if netResult == 0 {
                        outcomeBox.networkSucceeded = true
                    } else {
                        recordFailure(netResult)
                    }
                } else {
                    outcomeBox.networkSucceeded = true
                }

                if queueChanged {
                    let limitResult = vt_set_active_limit(session, configuration.maxActive)
                    if limitResult == 0 {
                        outcomeBox.queueSucceeded = true
                    } else {
                        recordFailure(limitResult)
                    }
                } else {
                    outcomeBox.queueSucceeded = true
                }

                if downloadPathChanged {
                    let pathResult = configuration.downloadPath.withCString {
                        vt_set_default_save_path(session, $0)
                    }
                    if pathResult == 0 {
                        outcomeBox.downloadPathSucceeded = true
                    } else {
                        recordFailure(pathResult)
                    }
                } else {
                    outcomeBox.downloadPathSucceeded = true
                }

                return firstFailureCode
            },
            onSuccess: { [weak self] in
                guard let self, self.sessionGeneration == applyGeneration, !self.isShuttingDown else { return }
                self.isApplyingSettings = false
                self.lastAppliedConfiguration = configuration
                self.lastAppliedProxyFailCloseReason = failCloseReason
                self.poll()
                if self.needsSettingsReapply {
                    self.needsSettingsReapply = false
                    self.applySettings()
                }
            },
            onFailure: { [weak self] message in
                guard let self, self.sessionGeneration == applyGeneration, !self.isShuttingDown else { return }
                self.isApplyingSettings = false
                if outcomeBox.proxySucceeded {
                    self.lastAppliedProxyFailCloseReason = failCloseReason
                }
                if var updated = self.lastAppliedConfiguration {
                    updated.seedRatioLimit = configuration.seedRatioLimit
                    if outcomeBox.proxySucceeded {
                        updated.proxyEnabled = configuration.proxyEnabled
                        updated.proxyHost = configuration.proxyHost
                        updated.proxyPort = configuration.proxyPort
                        updated.proxyUser = configuration.proxyUser
                        updated.proxyPassword = configuration.proxyPassword
                    }
                    if outcomeBox.networkSucceeded {
                        updated.port = configuration.port
                        updated.downloadLimit = configuration.downloadLimit
                        updated.uploadLimit = configuration.uploadLimit
                        updated.dht = configuration.dht
                        updated.upnp = configuration.upnp
                        updated.lsd = configuration.lsd
                        updated.bindAddress = configuration.bindAddress
                    }
                    if outcomeBox.queueSucceeded {
                        updated.maxActive = configuration.maxActive
                    }
                    if outcomeBox.downloadPathSucceeded {
                        updated.downloadPath = configuration.downloadPath
                    }
                    self.lastAppliedConfiguration = updated
                }
                let anyApplied =
                    outcomeBox.proxySucceeded
                    || outcomeBox.networkSucceeded
                    || outcomeBox.queueSucceeded
                    || outcomeBox.downloadPathSucceeded
                if anyApplied {
                    self.poll()
                }
                let detailMessage =
                    outcomeBox.firstErrorMessage
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                    ? message
                    : self.localizedError(outcomeBox.firstErrorMessage)
                self.showToast(L("Impostazioni non applicate"), kind: .error, detail: detailMessage)
                if self.needsSettingsReapply {
                    self.needsSettingsReapply = false
                    self.applySettings()
                }
            }
        )
        if !queued {
            isApplyingSettings = false
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    func showToast(
        _ text: String,
        kind: ToastMessage.Kind = .info,
        detail: String? = nil,
        actionTitle: String? = nil,
        action: ToastMessage.Action? = nil
    ) {
        let message = ToastMessage(
            kind: kind,
            text: text,
            detail: detail,
            actionTitle: actionTitle,
            action: action
        )
        toast = message
        if kind == .error {
            recordErrorToast(text)
            if let detail, !detail.isEmpty {
                recordErrorToast(detail)
            }
        }
        // VoiceOver cannot see the toast overlay: post it as an announcement so
        // errors and completions are not silent for screen-reader users.
        if kind != .info { announce(text) }
        toastTask?.cancel()
        // An actionable toast stays a little longer so it can be clicked.
        let delay: UInt64 = action == nil ? 4_000_000_000 : 7_000_000_000
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }

    /// Moves the SOCKS5 password between the Keychain and the 0600 file after
    /// the user changes the storage preference. The migration touches the
    /// Keychain and the filesystem, so it runs off the main thread.
    func setProxyPasswordStorage(inFile: Bool) {
        let value = Preferences.proxyPassword
        // Same pattern used for session work: the migration runs off the main
        // thread and hops back through DispatchQueue.main (Swift 6.1 rejects
        // capturing a task-isolated self in `Task.detached` + MainActor.run).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let migrated = Preferences.migrateProxyPasswordStorage(toFile: inFile, value: value)
            DispatchQueue.main.async {
                guard let self else { return }
                if !migrated {
                    Preferences.userDefaults.set(!inFile, forKey: PrefKey.proxyPasswordInFile)
                    self.showToast(
                        L(inFile ? "Operazione non riuscita." : "Impossibile salvare la password nel Portachiavi"),
                        kind: .error
                    )
                }
                self.applySettingsNow()
            }
        }
    }

    private func announce(_ text: String) {
        guard let app = NSApp, app.isRunning else { return }
        NSAccessibility.post(
            element: app,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    func control(
        _ action: String,
        id: String,
        onSuccess: (@MainActor () -> Void)? = nil
    ) {
        let queued = enqueueSessionOperation { session in
            id.withCString { idPointer in
                action.withCString { actionPointer in
                    vt_control(session, idPointer, actionPointer)
                }
            }
        } onSuccess: { [weak self] in
            onSuccess?()
            self?.poll()
        }
        // The command was refused because there is no session (startup, PEX
        // restart, shutdown): tell the user instead of letting the click vanish.
        if !queued {
            showToast(L("Motore non disponibile."), kind: .error)
        }
    }

    nonisolated static func preparedDestination(
        _ requested: String?,
        fallbackDownloadPath: String? = nil
    ) -> (path: String?, error: String?) {
        let raw = requested ?? fallbackDownloadPath ?? Preferences.userDefaults.string(forKey: PrefKey.downloadPath)
        let path = Preferences.resolvedDownloadPath(raw, fallback: fallbackDownloadPath)
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            return (nil, L("Impossibile creare la cartella di destinazione."))
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return (nil, L("La destinazione non è una cartella."))
        }
        guard fileManager.isWritableFile(atPath: path) else {
            return (nil, L("La cartella di destinazione non è scrivibile."))
        }

        return (path, nil)
    }

    func localizedError(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return L("Operazione non riuscita.") }
        let lower = value.lowercased()
        if lower.contains("torrent already exists") || lower.contains("duplicate") {
            return L("Questo torrent è già presente.")
        }
        if lower.contains("file exists") {
            return L("Esiste già un file con lo stesso nome nella cartella di destinazione.")
        }
        if lower.contains("no such file") || lower.contains("cannot stat") { return L("File non trovato.") }
        if lower.contains("permission") || lower.contains("operation not permitted") { return L("Permesso negato.") }
        // The bridge reports a proxy request without a host in Italian: without
        // this branch the English UI would show the raw C++ string.
        if lower.contains("host proxy non valido") { return L("Host proxy non valido") }
        if lower.contains("porta proxy") { return L("Porta proxy non valida") }
        if lower.contains("cross-device") { return L("Errore di lettura o scrittura sul disco.") }
        if lower.contains("invalid argument") { return L("Parametri non validi.") }
        if lower.contains("invalid")
            || lower.contains("parse")
            || lower.contains("missing info-hash")
            || lower.contains("mismatching info-hash")
            || lower.contains("missing or invalid 'info'")
            || lower.contains("missing info-dictionary")
            || lower.contains("not a dictionary")
            || lower.contains("missing name in torrent")
            || lower.contains("no files in torrent")
            || lower.contains("incorrect number of piece hashes")
            || lower.contains("too many pieces in torrent")
            || lower.contains("bencoded")
            || lower.contains("bencoding")
            || lower.contains("unsupported url protocol")
            || lower.contains("unknown meta version")
            || lower.contains("no file tree")
            || lower.contains("meta version 2")
            || lower.contains("file metadata does not match")
            || lower.contains("missing piece layer hashes")
            || lower.contains("no root hash")
            || lower.contains("do not describe the same data")
            || lower.contains("exceeds depth limit")
            || lower.contains("exceeds maximum size")
            || lower.contains("not a regular file")
        {
            return L("Link o file non valido.")
        }
        switch value {
        case "Motore non disponibile", "Motore non disponibile.": return L("Motore non disponibile.")
        case "Torrent non trovato": return L("Torrent non trovato")
        case "Metadati non disponibili": return L("In attesa dei metadati…")
        case "Comando non supportato": return L("Comando non supportato")
        case "Parametri non validi": return L("Parametri non validi.")
        case "La destinazione non è una cartella.": return L("La destinazione non è una cartella.")
        case "La cartella di destinazione non è scrivibile.": return L("La cartella di destinazione non è scrivibile.")
        case "Esiste già un file con lo stesso nome nella cartella di destinazione.":
            return L("Esiste già un file con lo stesso nome nella cartella di destinazione.")
        case "URL del tracker troppo lungo": return L("URL del tracker troppo lungo")
        case "URL del tracker non valido": return L("URL del tracker non valido")
        case "Troppi tracker": return L("Troppi tracker")
        case "Host proxy non valido": return L("Host proxy non valido")
        case "Porta proxy fuori intervallo (1–65535).": return L("Porta proxy non valida")
        case "Errore sconosciuto": return L("Errore sconosciuto")
        default: return RuntimeErrorLocalizer.torrent(value)
        }
    }
}
