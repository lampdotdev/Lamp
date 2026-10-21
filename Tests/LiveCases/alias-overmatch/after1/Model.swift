import Foundation
enum Mood { case happy, sad, angry }
struct Moods: Sequence { typealias Element = Mood; var all: [Mood]; func makeIterator() -> IndexingIterator<[Mood]> { all.makeIterator() } }
struct Stack<Element> { var items: [Element] = []; var top: Element? }
final class Holder { var moods: [Mood] = [.happy]; var ints = Stack<Int>(items: [1], top: 1) }
