import CoreMIDI
import Foundation

/// Standalone-only CoreMIDI input. The AUv3 extension never creates a client;
/// DAWs remain responsible for MIDI routing into the audio unit.
final class Vinegar303CoreMIDIInput {
    private let controller: Vinegar303MIDIController
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef: String] = [:]

    init(controller: Vinegar303MIDIController) {
        self.controller = controller

        let clientStatus = MIDIClientCreateWithBlock(
            "Vinegar303 MIDI Client" as CFString,
            &client
        ) { [weak self] notification in
            guard let self,
                  notification.pointee.messageID == .msgSetupChanged else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.refreshSources()
            }
        }
        guard clientStatus == noErr else {
            controller.reportInputError("CLIENT \(clientStatus)")
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(
            client,
            "Vinegar303 MIDI Input" as CFString,
            &inputPort
        ) { [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        }
        guard portStatus == noErr else {
            controller.reportInputError("PORT \(portStatus)")
            MIDIClientDispose(client)
            client = 0
            return
        }

        refreshSources()
    }

    deinit {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    private func refreshSources() {
        guard inputPort != 0 else { return }

        let sourceCount = MIDIGetNumberOfSources()
        var current: Set<MIDIEndpointRef> = []

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            current.insert(source)

            if connectedSources[source] == nil {
                let status = MIDIPortConnectSource(inputPort, source, nil)
                if status != noErr {
                    continue
                }
            }
            connectedSources[source] = displayName(for: source)
        }

        let removed = connectedSources.keys.filter { !current.contains($0) }
        for source in removed {
            MIDIPortDisconnectSource(inputPort, source)
            connectedSources.removeValue(forKey: source)
        }

        controller.updateInputStatus(
            devices: connectedSources.values.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        )
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        let count = Int(packetList.pointee.numPackets)
        guard count > 0 else { return }

        // MIDIPacketNext must walk the original packet-list memory. Walking a
        // copied MIDIPacket would calculate the next offset from local storage
        // and corrupt packet lists that contain more than one packet.
        let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) ?? 0
        var packetPointer = UnsafeMutableRawPointer(mutating: UnsafeRawPointer(packetList))
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<count {
            let packet = packetPointer.pointee
            if packet.length > 0 {
                let bytes = withUnsafeBytes(of: packet.data) {
                    Array($0.prefix(Int(packet.length)))
                }
                let messages = Vinegar303MIDIMessage.parse(bytes)
                if !messages.isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        for message in messages {
                            self.controller.receive(message)
                        }
                    }
                }
            }

            packetPointer = MIDIPacketNext(packetPointer)
        }
    }

    private func displayName(for source: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &value)
        guard status == noErr, let value else { return "MIDI DEVICE" }
        return value.takeRetainedValue() as String
    }
}

/// Output for the Launchkey Mini MK3's DAW/Session pad LEDs.
///
/// The controller is put into DAW mode and its Session pad mode explicitly.
/// Pad note messages are sent on channel 1, with velocity 5 selecting the
/// static red palette entry and velocity 0 clearing the pad.
final class Vinegar303LaunchkeyLEDOutput {
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var destination = MIDIEndpointRef()
    private(set) var connectionID = 0

    init() {
        let clientStatus = MIDIClientCreateWithBlock(
            "Vinegar303 Launchkey LED Client" as CFString,
            &client
        ) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else {
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.refreshDestination()
            }
        }
        guard clientStatus == noErr else { return }

        let portStatus = MIDIOutputPortCreate(
            client,
            "Vinegar303 Launchkey LED Output" as CFString,
            &outputPort
        )
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = 0
            return
        }

        refreshDestination()
    }

    deinit {
        shutdown()
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    func setLED(gate: Int, color: Vinegar303LaunchkeyPadColor) {
        guard let message = Vinegar303LaunchkeyPadMap.ledMessage(
            forGate: gate,
            color: color
        ) else { return }
        send(message)
    }

    /// Return the Launchkey to standalone mode and clear its pad LEDs.
    func shutdown() {
        guard destination != 0 else { return }
        clear()
        send([0x9F, 0x0C, 0x00])
        destination = 0
        connectionID &+= 1
    }

    private func refreshDestination() {
        guard outputPort != 0 else { return }

        var dawDestination = MIDIEndpointRef()
        var fallbackDestination = MIDIEndpointRef()

        for index in 0..<MIDIGetNumberOfDestinations() {
            let candidate = MIDIGetDestination(index)
            guard candidate != 0 else { continue }
            let name = displayName(for: candidate)
            guard name.localizedCaseInsensitiveContains("Launchkey") else { continue }

            if fallbackDestination == 0 {
                fallbackDestination = candidate
            }
            if name.localizedCaseInsensitiveContains("DAW") {
                dawDestination = candidate
                break
            }
        }

        let next = dawDestination != 0 ? dawDestination : fallbackDestination
        guard next != destination else { return }

        destination = next
        connectionID &+= 1
        guard next != 0 else { return }

        // DAW mode + Session pad mode. The Launchkey defaults to Session when
        // entering DAW mode, but sending the mode explicitly keeps this stable
        // if the user previously selected Drum mode.
        send([0x9F, 0x0C, 0x7F])
        send([0xBF, 0x03, 0x02])
        clear()
    }

    private func clear() {
        for gate in 0..<Vinegar303LaunchkeyPadMap.allNotes.count {
            setLED(gate: gate, color: .off)
        }
    }

    private func send(_ bytes: [UInt8]) {
        guard destination != 0, outputPort != 0 else { return }

        var storage = [UInt8](repeating: 0, count: 64)
        storage.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let list = base.assumingMemoryBound(to: MIDIPacketList.self)
            var packet = MIDIPacketListInit(list)
            bytes.withUnsafeBufferPointer { buffer in
                guard let data = buffer.baseAddress else { return }
                packet = MIDIPacketListAdd(
                    list,
                    raw.count,
                    packet,
                    0,
                    bytes.count,
                    data
                )
            }
            _ = MIDISend(outputPort, destination, list)
        }
    }

    private func displayName(for endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(
            endpoint,
            kMIDIPropertyDisplayName,
            &value
        )
        guard status == noErr, let value else { return "MIDI DEVICE" }
        return value.takeRetainedValue() as String
    }
}
