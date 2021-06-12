//
//  World.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 13/1/21.
//

import Foundation


// TODO: make World threadsafe
class World {
  var name: Identifier
  var dimension: Identifier
  var hashedSeed: Int
  var isDebug: Bool
  var isFlat: Bool
  
  var age: Int = -1
  var downloadingTerrain: Bool = true
  
  private(set) var chunks: [ChunkPosition: Chunk] = [:]
  var lighting: [ChunkPosition: ChunkLighting] = [:]
  
  var chunkCount: Int {
    return chunks.count
  }
  
  private var chunkThread = DispatchQueue(label: "worldChunks")
  private var managers: Managers
  
  private var batchingEnabled = true
  private var eventBatch = EventBatch()
  
  init(info: World.Info, managers: Managers) {
    self.managers = managers
    
    name = info.name
    dimension = info.dimension
    hashedSeed = info.hashedSeed
    isFlat = info.isFlat
    isDebug = info.isDebug
  }
  
  func setInfo(_ info: World.Info) {
    name = info.name
    dimension = info.dimension
    hashedSeed = info.hashedSeed
    isFlat = info.isFlat
    isDebug = info.isDebug
  }
  
  // Batching
  
  func enableBatching() {
    batchingEnabled = true
    eventBatch = EventBatch()
  }
  
  func disableBatching() {
    batchingEnabled = false
  }
  
  func processBatch(filter: ((DeltaClient.Event) -> Bool)? = nil) -> [DeltaClient.Event] {
    // copy and clear current batch
    let batch = eventBatch
    eventBatch = EventBatch()
    
    // filter events if `filter` != nil
    var acceptedEvents: [DeltaClient.Event] = batch.events
    if let filter = filter {
      acceptedEvents = acceptedEvents.filter(filter)
      
      // add rejected events to next batch
      let rejectedEvents = batch.events.filter({ !filter($0) })
      rejectedEvents.forEach { eventBatch.add($0) }
    }
    
    // process events
    acceptedEvents.forEach { event in
      handle(event)
    }
    
    return acceptedEvents
  }
  
  func handle(_ event: DeltaClient.Event) {
    switch event {
      case let event as Event.SetBlock:
        setBlock(at: event.position, to: event.newState, bypassBatching: true)
      case let event as Event.AddChunk:
        addChunk(event.chunk, at: event.position, bypassBatching: true)
      case let event as Event.UpdateChunk:
        updateChunk(at: event.position, with: event.data, bypassBatching: true)
      case let event as Event.RemoveChunk:
        removeChunk(at: event.position, bypassBatching: true)
      default:
        break
    }
  }
  
  // Block
  
  func setBlock(at position: Position, to state: UInt16, bypassBatching: Bool = false) {
    if batchingEnabled && !bypassBatching {
      let event = Event.SetBlock(
        position: position,
        newState: state)
      eventBatch.add(event)
    } else if let chunk = chunks[position.chunk] {
      chunk.setBlock(at: position.relativeToChunk, to: state)
    } else {
      log.warning("Cannet set block in non-existent chunk, chunkPosition=\(position.chunk)")
    }
  }
  
  func setBlock(at position: Position, inChunkAt chunkPosition: ChunkPosition, to newState: UInt16, bypassBatching: Bool = false) {
    if batchingEnabled && !bypassBatching {
      var absolutePosition = position
      absolutePosition.x += chunkPosition.chunkX * Chunk.width
      absolutePosition.z += chunkPosition.chunkZ * Chunk.depth
      let event = Event.SetBlock(
        position: absolutePosition,
        newState: newState)
      eventBatch.add(event)
    } else if let chunk = chunks[chunkPosition] {
      chunk.setBlock(at: position, to: newState)
    } else {
      log.warning("Cannot set block in non-existent chunk, chunkPosition=\(chunkPosition)")
    }
  }
  
  func getBlock(at position: Position) -> UInt16 {
    if let chunk = chunks[position.chunk] {
      return chunk.getBlock(at: position.relativeToChunk)
    } else {
      log.warning("get block called for non existent chunk: \(position.chunk)")
      return 0 // air
    }
  }
  
  // Chunk
  
  func chunk(at chunkPosition: ChunkPosition) -> Chunk? {
    return chunks[chunkPosition]
  }
  
  func neighbours(ofChunkAt chunkPosition: ChunkPosition) -> [CardinalDirection: Chunk] {
    let neighbourPositions = chunkPosition.allNeighbours
    var neighbourChunks: [CardinalDirection: Chunk] = [:]
    for (direction, neighbourPosition) in neighbourPositions {
      if let neighbour = chunk(at: neighbourPosition) {
        neighbourChunks[direction] = neighbour
      }
    }
    return neighbourChunks
  }
  
  func addChunk(_ chunk: Chunk, at position: ChunkPosition, bypassBatching: Bool = false) {
    if batchingEnabled && !bypassBatching {
      let event = Event.AddChunk(position: position, chunk: chunk)
      eventBatch.add(event)
    } else {
      chunks[position] = chunk
    }
  }
  
  func updateChunk(at position: ChunkPosition, with data: UnpackedChunkData, bypassBatching: Bool = false) {
    if batchingEnabled && !bypassBatching {
      let event = Event.UpdateChunk(position: position, data: data)
      eventBatch.add(event)
    } else {
      if let chunk = chunk(at: position) {
        chunk.blockEntities = data.blockEntities
        chunk.heightMaps = data.heightMaps
        chunk.ignoreOldData = data.ignoreOldData
        data.presentSections.forEach { sectionIndex in
          chunk.setSection(atIndex: sectionIndex, to: data.sections[sectionIndex])
        }
      }
    }
  }
  
  func addChunkData(_ chunkData: ChunkData) {
    chunkThread.async {
      do {
        let unpackedChunkData = try chunkData.unpack(blockPaletteManager: self.managers.blockPaletteManager)
        if self.chunks.keys.contains(unpackedChunkData.chunkPosition) {
          self.updateChunk(at: unpackedChunkData.chunkPosition, with: unpackedChunkData)
        } else {
          let chunk = Chunk(
            heightMaps: unpackedChunkData.heightMaps,
            ignoreOldData: unpackedChunkData.ignoreOldData,
            biomes: unpackedChunkData.biomes,
            sections: unpackedChunkData.sections,
            blockEntities: unpackedChunkData.blockEntities)
          self.addChunk(chunk, at: unpackedChunkData.chunkPosition)
        }
      } catch {
        log.error("Failed to unpack chunk at \(chunkData.position)")
      }
    }
  }
  
  func removeChunk(at position: ChunkPosition, bypassBatching: Bool = false) {
    let event = Event.RemoveChunk(position: position)
    if batchingEnabled && !bypassBatching {
      eventBatch.add(event)
    } else {
      self.chunks.removeValue(forKey: position)
    }
  }
  
  func finishDownloadingTerrain() {
    // once this runs on the thread the last chunk will have unpacked
    chunkThread.async {
      self.downloadingTerrain = false
      DeltaClientApp.eventManager.triggerEvent(.downloadedTerrain)
    }
  }
}
