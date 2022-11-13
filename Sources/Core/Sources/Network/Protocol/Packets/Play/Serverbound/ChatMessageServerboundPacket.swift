import Foundation

public struct ChatMessageServerboundPacket: ServerboundPacket {
  public static let id: Int = 0x03

  public var message: String

  public init(_ message: String) {
    self.message = message
  }

  public func writePayload(to writer: inout PacketWriter) {
    writer.writeString(message)
  }
}
