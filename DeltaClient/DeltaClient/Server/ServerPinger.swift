//
//  ServerPinger.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 20/1/21.
//

import Foundation
import os

class ServerPinger: Hashable, ObservableObject {
  @Published var pingResult: PingResult? = nil
  
  var eventManager: EventManager
  var descriptor: ServerDescriptor
  var connection: ServerConnection
  var packetRegistry: PacketRegistry
  
  // Init
  
  init(_ descriptor: ServerDescriptor) {
    self.eventManager = EventManager()
    self.descriptor = descriptor
    self.packetRegistry = PacketRegistry.createDefault()
    self.connection = ServerConnection(host: descriptor.host, port: descriptor.port, eventManager: self.eventManager)
    self.connection.setPacketHandler(handlePacket)
  }
  
  // Networking
  
  func ping() {
    pingResult = nil
    eventManager.registerOneTimeEventHandler({ event in
      self.connection.handshake(nextState: .status)
      
      let statusRequest = StatusRequestPacket()
      self.connection.sendPacket(statusRequest)
    }, eventName: "connectionReady")
    connection.restart()
  }
  
  func handlePacket(_ packetReader: PacketReader) {
    do {
      var reader = packetReader
      if let packetState = connection.state.toPacketState() {
        guard let packetType = packetRegistry.getClientboundPacketType(withId: reader.packetId, andState: packetState) else {
          Logger.debug("non-existent packet received with id 0x\(String(reader.packetId, radix: 16))")
          return
        }
        let packet = try packetType.init(from: &reader)
        try packet.handle(for: self)
      }
    } catch {
      Logger.debug("failed to handle packet: \(error)")
    }
  }
  
  // Conformance: Hashable
  
  static func == (lhs: ServerPinger, rhs: ServerPinger) -> Bool {
    return lhs.descriptor == rhs.descriptor
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(descriptor)
  }
}
