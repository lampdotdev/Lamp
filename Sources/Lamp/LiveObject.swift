import Foundation
import MachO

/// A changed file compiled for the open app (LiveReload) defines its types over again: their metadata, descriptors
/// and protocol descriptors come out in the library as copies of the app's, and the compiler's code refers to its
/// own copies directly (`adrp`/`add` to the full metadata), which no symbol pointer reaches. A value of a struct or
/// an enum then carries one copy's identity or the other's: a cast (`as? Point`) between them fails, a conformance
/// added in the change isn't found for the app's values, and SwiftUI, comparing the type of a view's body,
/// takes the whole subtree for a new one and loses every state in it. So before the object is linked, each such
/// definition is renamed (`$lampcopy`), and every reference from code to it becomes a load through the global offset
/// table of a weak undefined symbol with the original name: the library then asks for the app's copy, which
/// `LampLive` binds (or, for a type the app doesn't have, the library's own). A protocol's descriptor is treated the
/// same, so an existential of the app's protocol is the same type in both. References from data (the library's own
/// metadata and conformance records) stay on the copies, and `LampLive` points the records at the app's descriptors.
/// Types named in `kept` (an enum that gained cases, whose metadata the change must bring) are left as they are.
/// Anything the rewrite doesn't understand (a reference shaped another way, an object laid out otherwise) is refused,
/// with why, and the change reopens the app.
enum LiveObject {
    /// The suffix a copy's definition is renamed with.
    static let copySuffix = "$lampcopy"

    /// Whether a defined symbol names what a type or protocol is to the runtime: a nominal type's metadata (`N`,
    /// `Mf` its full form) or descriptor (`Mn`), a protocol's descriptor (`Mp`), or a conformance's descriptor (`Mc`)
    /// and witness table (`WP`), by which the runtime tells generic types made with one conformance from those made
    /// with another. Or, when it's private to its file (`local`), the addressor of a stored global or static (`vau`):
    /// a public one's calls go through a symbol pointer that `LampLive` points at the app's storage, but a private
    /// one's are direct, so the library would keep a second copy of the value, starting over.
    static func isIdentity(_ name: String, local: Bool = false) -> Bool {
        guard name.hasPrefix("_$s"), !name.hasSuffix(copySuffix) else { return false }
        if local, name.hasSuffix("vau") { return true }
        if name.hasSuffix("Mp") || name.hasSuffix("Mc") || name.hasSuffix("WP") { return true }
        for suffix in ["Mf", "N", "Mn"] where name.hasSuffix(suffix) {
            let kind = name.dropLast(suffix.count).last
            return kind == "V" || kind == "O" || kind == "C"
        }
        return false
    }

    /// Rewrites the object at `path` in place. `kept` names the types whose copies the library keeps for itself, by
    /// their mangled name with the module ("3App4MoodO"), as `mangledType` gives it; those found among the object's
    /// types are added to `matched`. Nil when done, else why not.
    static func rewrite(_ path: String, kept: [String] = [], matched: inout Set<String>) -> String? {
        guard var bytes = FileManager.default.contents(atPath: path).map({ [UInt8]($0) }) else { return "the object couldn't be read" }
        guard let problem = rewrite(&bytes, kept: kept, matched: &matched) else {
            return FileManager.default.createFile(atPath: path, contents: Data(bytes)) ? nil : "the object couldn't be written"
        }
        return problem
    }

    /// A type's mangled name with its module, from its name as the layout check has it ("Outer.Inner") and its
    /// kind ("V" a struct, "O" an enum, "C" a class): "3App5OuterV5InnerV".
    static func mangledType(_ name: String, module: String, kind: String) -> String {
        "\(module.utf8.count)\(module)" + name.split(separator: ".").map { "\($0.utf8.count)\($0)" + kind }.joined()
    }

    private struct Section { var name: String; var offset: Int; var size: Int; var reloff: Int; var nreloc: Int; var index: Int }

    static func rewrite(_ bytes: inout [UInt8], kept: [String], matched: inout Set<String>) -> String? {
        func u32(_ at: Int) -> UInt32 { bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt32.self) } }
        func u64(_ at: Int) -> UInt64 { bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt64.self) } }
        func put32(_ value: UInt32, _ at: Int) { bytes.withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: at, as: UInt32.self) } }
        guard bytes.count >= MemoryLayout<mach_header_64>.size, u32(0) == MH_MAGIC_64, u32(4) == CPU_TYPE_ARM64 else { return "not an arm64 object" }
        let ncmds = Int(u32(16))
        var sections: [Section] = []
        var symtab: (offset: Int, symoff: Int, nsyms: Int, stroff: Int, strsize: Int)?
        var dysymtab: Int?
        var at = MemoryLayout<mach_header_64>.size
        for _ in 0..<ncmds {
            guard at + 8 <= bytes.count else { return "a load command runs past the end" }
            let cmd = u32(at), size = Int(u32(at + 4))
            switch cmd {
            case UInt32(LC_SEGMENT_64):
                let nsects = Int(u32(at + 64))
                var section = at + MemoryLayout<segment_command_64>.size
                for _ in 0..<nsects {
                    let name = String(decoding: bytes[section..<(section + 16)].prefix { $0 != 0 }, as: UTF8.self)
                    let segment = String(decoding: bytes[(section + 16)..<(section + 32)].prefix { $0 != 0 }, as: UTF8.self)
                    sections.append(Section(name: segment + "," + name, offset: Int(u32(section + 48)), size: Int(u64(section + 40)),
                                            reloff: Int(u32(section + 56)), nreloc: Int(u32(section + 60)), index: sections.count + 1))
                    section += MemoryLayout<section_64>.size
                }
            case UInt32(LC_SYMTAB):
                symtab = (at, Int(u32(at + 8)), Int(u32(at + 12)), Int(u32(at + 16)), Int(u32(at + 20)))
            case UInt32(LC_DYSYMTAB):
                dysymtab = at
            default: break
            }
            at += size
        }
        guard let symtab, let dysymtab else { return "the object has no symbol table" }
        // The symbol table, then the string table, must be the last things in the file: both grow.
        guard symtab.stroff == symtab.symoff + symtab.nsyms * 16, symtab.stroff + symtab.strsize == bytes.count else {
            return "the object isn't laid out as expected"
        }
        func symbolName(_ index: Int) -> String {
            let strx = Int(u32(symtab.symoff + index * 16))
            return String(decoding: bytes[(symtab.stroff + strx)...].prefix { $0 != 0 }, as: UTF8.self)
        }
        // The definitions to rename, by symbol index, each with the index of the undefined symbol that takes its name.
        var renamed: [Int: Int] = [:]
        var added: [(name: String, type: UInt8, desc: UInt16)] = []
        var names: [String] = []
        for index in 0..<symtab.nsyms {
            let type = bytes[symtab.symoff + index * 16 + 4]
            guard type & UInt8(N_STAB) == 0 else { continue }
            let name = symbolName(index)
            // A type another changed file defines is referred to here as any other file's would be: made weak too,
            // or the linker would take the strong reference's word that the type must be found at load.
            if type & UInt8(N_TYPE) == UInt8(N_UNDF), isIdentity(name) {
                let desc = symtab.symoff + index * 16 + 6
                let value = UInt16(bytes[desc]) | UInt16(bytes[desc + 1]) << 8 | UInt16(N_WEAK_REF)
                bytes[desc] = UInt8(value & 0xFF)
                bytes[desc + 1] = UInt8(value >> 8)
                continue
            }
            guard type & UInt8(N_TYPE) == UInt8(N_SECT), isIdentity(name, local: type & UInt8(N_EXT) == 0) else { continue }
            if let keep = kept.first(where: { name.hasPrefix("_$s" + $0) }) { matched.insert(keep); continue }
            renamed[index] = symtab.nsyms + added.count
            added.append((name, UInt8(N_UNDF) | UInt8(N_EXT), UInt16(N_WEAK_REF)))
            names.append(name)
        }
        guard !renamed.isEmpty else { return nil }
        // Every reference from code becomes a load through the table. Each pair is an `adrp` and an `add` to the
        // same symbol; the `add` becomes `ldr`, and the linker fills in the table's entry.
        for section in sections where section.nreloc > 0 {
            for r in 0..<section.nreloc {
                let reloc = section.reloff + r * 8
                let address = Int(Int32(bitPattern: u32(reloc))), info = u32(reloc + 4)
                let symbolnum = Int(info & 0xFFFFFF), isExtern = info & (1 << 27) != 0, type = Int(info >> 28)
                guard isExtern, let undefined = renamed[symbolnum] else { continue }
                let code = section.name == "__TEXT,__text"
                switch type {
                case Int(ARM64_RELOC_UNSIGNED.rawValue), Int(ARM64_RELOC_SUBTRACTOR.rawValue):
                    // Data: the library's own metadata and records, which keep its copies.
                    guard !code else { return "code holds a type's address in \(section.name)" }
                case Int(ARM64_RELOC_BRANCH26.rawValue):
                    // A call to a private addressor: made to the app's through the symbol's stub.
                    guard code, names[undefined - symtab.nsyms].hasSuffix("vau") else { return "a type's address is called" }
                    put32(UInt32(undefined) | (info & 0x0F00_0000) | (UInt32(ARM64_RELOC_BRANCH26.rawValue) << 28), reloc + 4)
                case Int(ARM64_RELOC_PAGE21.rawValue):
                    guard code, address + 4 <= section.size else { return "a page reference to a type outside the code" }
                    let at = section.offset + address
                    guard u32(at) & 0x9F00_0000 == 0x9000_0000 else { return "a page reference that isn't adrp" }
                    guard r == 0 || Int(u32(reloc - 8 + 4) >> 28) != Int(ARM64_RELOC_ADDEND.rawValue) else { return "a type referred to at an offset" }
                    put32(UInt32(undefined) | (info & 0x0F00_0000) | (UInt32(ARM64_RELOC_GOT_LOAD_PAGE21.rawValue) << 28), reloc + 4)
                case Int(ARM64_RELOC_PAGEOFF12.rawValue):
                    guard code, address + 4 <= section.size else { return "an offset reference to a type outside the code" }
                    let at = section.offset + address
                    let insn = u32(at)
                    // `add Xd, Xn, #imm` (64-bit, unshifted, the immediate the linker's) to `ldr Xd, [Xn]`.
                    guard insn & 0xFFC0_0000 == 0x9100_0000, insn & 0x003F_FC00 == 0 else { return "a type referred to by an instruction that isn't add" }
                    put32(0xF940_0000 | (insn & 0x3FF), at)
                    put32(UInt32(undefined) | (info & 0x0F00_0000) | (UInt32(ARM64_RELOC_GOT_LOAD_PAGEOFF12.rawValue) << 28), reloc + 4)
                default:
                    return "a type referred to in a way the rewrite doesn't know (\(type))"
                }
            }
        }
        // The definitions keep their place in the table under new names, and the undefined symbols go after every
        // other, where the undefined ones are listed: only their count changes.
        var strings = Array(bytes[symtab.stroff...])
        var table = Array(bytes[symtab.symoff..<symtab.stroff])
        for (index, _) in renamed {
            let strx = UInt32(strings.count)
            strings += Array((symbolName(index) + copySuffix).utf8) + [0]
            table.withUnsafeMutableBytes { $0.storeBytes(of: strx, toByteOffset: index * 16, as: UInt32.self) }
        }
        for symbol in added {
            var entry = [UInt8](repeating: 0, count: 16)
            entry.withUnsafeMutableBytes {
                $0.storeBytes(of: UInt32(strings.count), toByteOffset: 0, as: UInt32.self)
                $0.storeBytes(of: symbol.type, toByteOffset: 4, as: UInt8.self)
                $0.storeBytes(of: symbol.desc, toByteOffset: 6, as: UInt16.self)
            }
            strings += Array(symbol.name.utf8) + [0]
            table += entry
        }
        bytes.removeSubrange(symtab.symoff...)
        bytes += table + strings
        put32(UInt32(symtab.nsyms + added.count), symtab.offset + 12)
        put32(UInt32(symtab.symoff + table.count), symtab.offset + 16)
        put32(UInt32(strings.count), symtab.offset + 20)
        // dysymtab: iundefsym at +24, nundefsym at +28.
        guard Int(u32(dysymtab + 24)) + Int(u32(dysymtab + 28)) == symtab.nsyms else { return "the undefined symbols aren't last" }
        put32(u32(dysymtab + 28) + UInt32(added.count), dysymtab + 28)
        return nil
    }
}
