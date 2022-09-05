import simd

struct GUIColoredString: GUIElement {
  var text: String
  var color: SIMD4<Float>
  var outlineColor: SIMD4<Float>?

  init(_ text: String, _ color: SIMD4<Float>, outlineColor: SIMD4<Float>? = nil) {
    self.text = text
    self.color = color
    self.outlineColor = outlineColor
  }

  func meshes(context: GUIContext) throws -> [GUIElementMesh] {
    return (try? GUIElementMesh(
      text: text,
      font: context.font,
      fontArrayTexture: context.fontArrayTexture,
      color: color,
      outlineColor: outlineColor
    )).map { [$0] } ?? []
  }
}
