import Foundation
import FindPhoneKit

func pad(_ s: String, _ width: Int) -> String {
    s.padding(toLength: width, withPad: " ", startingAt: 0)
}

func bar(_ rssi: Int, width: Int = 24,
         fill: Character = "#", empty: Character = ".") -> String {
    let filled = Int((Proximity.fraction(rssi) * Double(width)).rounded())
    return String(repeating: fill, count: filled)
        + String(repeating: empty, count: width - filled)
}

private let sparkLevels = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

func sparkline(_ readings: ArraySlice<Reading>) -> String {
    readings.map { sparkLevels[Int((Proximity.fraction($0.rssi) * 7.0).rounded())] }.joined()
}
