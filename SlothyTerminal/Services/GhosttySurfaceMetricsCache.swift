import Foundation

struct GhosttySurfaceMetricsCache {
  private var lastSurfaceSize: (width: UInt32, height: UInt32)?
  private var lastContentScale: (x: Double, y: Double)?

  mutating func shouldApplySurfaceSize(width: UInt32, height: UInt32) -> Bool {
    guard width > 0,
          height > 0
    else {
      return false
    }

    let nextSize = (width: width, height: height)

    if let lastSurfaceSize,
       lastSurfaceSize == nextSize
    {
      return false
    }

    lastSurfaceSize = nextSize
    return true
  }

  mutating func shouldApplyContentScale(
    x: Double,
    y: Double,
    tolerance: Double = 0.0001
  ) -> Bool {
    guard x > 0,
          y > 0
    else {
      return false
    }

    if let lastContentScale,
       abs(lastContentScale.x - x) <= tolerance,
       abs(lastContentScale.y - y) <= tolerance
    {
      return false
    }

    lastContentScale = (x: x, y: y)
    return true
  }

  mutating func reset() {
    lastSurfaceSize = nil
    lastContentScale = nil
  }
}
