
import Foundation
import MachO

#if DEBUG
let origFile = ("/Users/charlotte/Downloads/old_Nexus.dylib" as NSString).expandingTildeInPath
let file = NSTemporaryDirectory()+"/"+UUID().uuidString+".dylib"
#else
let origFile = ProcessInfo.processInfo.arguments[1]
let file = ProcessInfo.processInfo.arguments[2]
#endif

print("patching", origFile, file)

try FileManager.default.copyItem(atPath: origFile, toPath: file)

let ekhandle = dlopen("/Library/TweakInject/ellekit.dylib", RTLD_NOW);

let hookMemory = {
    unsafeBitCast(dlsym(ekhandle, "MSHookMemory"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, size_t) -> Void).self)
}()

let hookFunction = {
    unsafeBitCast(dlsym(ekhandle, "MSHookFunction"), to: (@convention (c) (UnsafeRawPointer, UnsafeRawPointer, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void).self)
}()

@_silgen_name("_dyld_get_prog_image_header")
func _dyld_get_prog_image_header() -> UnsafeMutablePointer<mach_header_64>

typealias FileHandleC = UnsafeMutablePointer<FILE>
extension FileHandleC {
    @inline(__always)
    func readData(ofLength count: Int) -> UnsafeMutableRawPointer {
        let alloc = malloc(count)
        fread(alloc, 1, count, self)
        return alloc!
    }
    
    @inline(__always)
    func write<S: FixedWidthInteger>(_ num: S) {
        var buf: [S] = [num]
        fwrite(&buf, 1, MemoryLayout.size(ofValue: num), self)
    }
    
    @discardableResult @inline(__always)
    func seek(toFileOffset offset: UInt64) -> UnsafeMutablePointer<FILE> {
        var pos: fpos_t = .init(offset)
        fsetpos(self, &pos)
        return self
    }
    
    @inline(__always)
    var offsetInFile: UInt64 {
        var pos: fpos_t = 0
        fgetpos(self, &pos)
        return .init(pos)
    }
    
    @inline(__always)
    func close() {
        fclose(self)
    }
}

struct _cfstring {
    var isa: UInt64
    let flags: Int32
    let str: UnsafePointer<Int8>?
    let length: Int
}

let uikitiOSPath = "/System/Library/Frameworks/UIKit.framework/UIKit"
let uikitMacPath = "/System/iOSSupport/System/Library/Frameworks/UIKit.framework/Versions/A/UIKit"
let substrateMacPath = "/Library/TweakInject/ellekit.dylib"

var cfStringISA: UInt64 = 0

func patchArch(_ path: String) {
    guard let handle = fopen(path, "r+b") else {
        print("Failed to open destination file")
        return
    }
        
    defer { handle.close() }
    
    let machHeaderPointer = handle
        .readData(ofLength: MemoryLayout<mach_header_64>.size)
    
    defer { machHeaderPointer.deallocate() }
        
    if machHeaderPointer.assumingMemoryBound(to: mach_header_64.self).pointee.magic == FAT_CIGAM {
        // we have a fat binary
        // get our current cpu subtype
        let nslices = handle
            .seek(toFileOffset: 0x4)
            .readData(ofLength: MemoryLayout<UInt32>.size)
            .assumingMemoryBound(to: UInt32.self)
            .pointee.bigEndian
                                
        for i in 0..<nslices {
            let slice_ptr = handle
                .seek(toFileOffset: UInt64(8 + (Int(i) * 20)))
                .readData(ofLength: MemoryLayout<fat_arch>.size)
                .assumingMemoryBound(to: fat_arch.self)
            
            let slice = slice_ptr.pointee
            
            defer { slice_ptr.deallocate() }
            
            if slice.cpusubtype == 0x2000000 { // old abi
                
                handle.seek(toFileOffset: UInt64(8 + (Int(i) * 20)) + 0x4)
                
                var bytes: UInt32 = 0x2000080
                
                print("ORIG:", String(format: "%02X", slice.cpusubtype))
                //fwrite(&bytes, 4, 1, handle)
                
                let slice_new = handle
                    .seek(toFileOffset: UInt64(8 + (Int(i) * 20)))
                    .readData(ofLength: MemoryLayout<fat_arch>.size)
                    .assumingMemoryBound(to: fat_arch.self)
                    .pointee
                
                print("PATCHED SLICE:", String(format: "%02X", slice_new.cpusubtype))
            }
            
            if slice.cputype.bigEndian == CPU_TYPE_ARM64 {
                                                            
                let headerPointer = handle
                    .seek(toFileOffset: UInt64(slice.offset.bigEndian))
                    .readData(ofLength: MemoryLayout<mach_header_64>.size)
                    .assumingMemoryBound(to: mach_header_64.self)
                
                let header = headerPointer.pointee
                
                print("ORIG:", String(format: "%02X", header.cpusubtype.bigEndian))
                
                if header.cpusubtype.bigEndian == 0x2000000 || header.cpusubtype.bigEndian == 0x2000080 { // 64e
                                        
                    handle.seek(toFileOffset: UInt64(slice.offset.bigEndian) + 8)
                    
                    var bytes: UInt32 = UInt32(0x80000002)
                    
                    //fwrite(&bytes, 4, 1, handle)
                    
                    let headerNew = handle
                        .seek(toFileOffset: UInt64(slice.offset.bigEndian))
                        .readData(ofLength: MemoryLayout<mach_header_64>.size)
                        .assumingMemoryBound(to: mach_header_64.self)
                        .pointee
                    
                    print("PATCHED:", String(format: "%02X", headerNew.cpusubtype.bigEndian))
                    
                } else {
                    continue
                }
                
                var index: UInt64 = 0x20
                
                for _ in 0..<header.ncmds {
                    let cmdPtr = handle
                        .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                        .readData(ofLength: MemoryLayout<load_command>.size)
                        .assumingMemoryBound(to: load_command.self)
                    
                    defer { cmdPtr.deallocate() }
                    
                    let cmd = cmdPtr.pointee
                                        
                    if cmd.cmd == LC_SEGMENT_64 {
                        let segmentCmd = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                            .readData(ofLength: MemoryLayout<segment_command_64>.size)
                            .assumingMemoryBound(to: segment_command_64.self)
                            .pointee
                        
                        
                        let segnameString = withUnsafePointer(to: segmentCmd.segname) {
                            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                                String(cString: $0)
                            }
                        }
                        
                        let sections = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index + UInt64(MemoryLayout<segment_command_64>.stride))
                            .readData(ofLength: Int(segmentCmd.vmsize))
                            .assumingMemoryBound(to: section_64.self)
                                                
                        UnsafeBufferPointer(start: sections, count: Int(segmentCmd.nsects)).enumerated().forEach { idx, section in
                            let sectName = withUnsafePointer(to: section.sectname) {
                                $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                                    String(cString: $0)
                                }
                            }
                            
                            print(sectName)
                                                
                            // __objc_selrefs
                            #if false
                            if sectName.hasPrefix("__objc_const") {
                                
                                struct objc_meth_hdr {
                                    var type: UInt32
                                    var count: UInt32
                                }
                                
                                let hdr = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: MemoryLayout<objc_meth_hdr>.size)
                                    .assumingMemoryBound(to: objc_meth_hdr.self)
                                    .pointee
                                
                                struct objc_meth2 {
                                    var name: UInt64
                                    var types: UInt64
                                    var imp: UInt64
                                }
                                
                                let meths = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: MemoryLayout<objc_meth_hdr>.size*Int(hdr.count))
                                    .assumingMemoryBound(to: objc_meth2.self)
                                
                                print(section.size)
                                
                                let arr = Array(UnsafeBufferPointer(start: meths, count: Int(section.size) / MemoryLayout<objc_meth2>.size))
                                for (index) in 0..<arr.count {
                                    
                                    var meth = arr[index]
                                    let methoff = UInt64(slice.offset.bigEndian) + UInt64(section.offset) + UInt64(index*MemoryLayout<UInt64>.size)
                                    
                                    print(meth)
                                                                                                            
                                    handle.seek(toFileOffset: methoff)
                                    print(String(format: "methb4: 0x%02llX", handle.readData(ofLength: 8).assumingMemoryBound(to: UInt64.self).pointee))
                                    var newMeth = (meth.name & 0x000000ffffffffff)
                                    handle.seek(toFileOffset: methoff)
                                    fwrite(&newMeth, MemoryLayout.size(ofValue: newMeth), 1, handle)
                                    
                                    handle.seek(toFileOffset: methoff)
                                    
                                    print(String(format: "methnew: 0x%02llX", handle.readData(ofLength: 8).assumingMemoryBound(to: UInt64.self).pointee))
                                }
                            }
                            
                            if sectName.hasPrefix("__objc_selrefs") {
                                let strings = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: Int(section.size))
                                    .assumingMemoryBound(to: UInt64.self)
                                
                                UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<UInt64>.size).enumerated().forEach { index, sel in
                                    
                                    var sel = sel
                                    let seloff = UInt64(slice.offset.bigEndian) + UInt64(section.offset) + UInt64(index*MemoryLayout<UInt64>.size)
                                    
                                    print(String(format: "sel: 0x%02llX", sel))
                                    
                                    handle.seek(toFileOffset: seloff)
                                    print(String(format: "selbefore: 0x%02llX", handle.readData(ofLength: 8).assumingMemoryBound(to: UInt64.self).pointee))
                                    var newSel = (sel & 0x0000000fffffffff)
                                    handle.seek(toFileOffset: seloff)
                                    fwrite(&newSel, MemoryLayout.size(ofValue: newSel), 1, handle)
                                    
                                    handle.seek(toFileOffset: seloff)
                                    
                                    print(String(format: "selnew: 0x%02llX", handle.readData(ofLength: 8).assumingMemoryBound(to: UInt64.self).pointee))
                                    
                                }
                            }
                            #endif
                            
                            struct objc_class {
                                var isa: UInt64
                                var superclass: UInt64
                                var cache: UInt64
                                var vtable: UInt64
                                var data: UInt64
                            }
                            
                            /*if sectName.hasPrefix("__objc_classrefs") {
                                let strings = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: Int(section.size))
                                    .assumingMemoryBound(to: UInt64.self)
                                
                                UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<UInt64>.size).enumerated().forEach { index, cls in
                                    
                                    let clsoff = UInt64(slice.offset.bigEndian) + (cls & 0x0000000fffffffff)
                                    
                                    print(String(format: "clsoff: 0x%02llX", clsoff))
                                    print(String(format: "classref: 0x%02llX", cls))
                                    
                                    var cls = handle
                                        .seek(toFileOffset: clsoff)
                                        .readData(ofLength: MemoryLayout<objc_class>.size)
                                        .assumingMemoryBound(to: objc_class.self)
                                        .pointee
                                    
                                    print("--- CLASS REF ----")
                                    print(String(format: "0x%02llX", cls.isa))
                                    print(String(format: "0x%02llX", cls.superclass))
                                    print(String(format: "0x%02llX", cls.cache))
                                    print(String(format: "0x%02llX", cls.vtable))
                                    print(String(format: "0x%02llX", cls.data))
                                    
                                    if String(format: "0x%02llX", cls.isa).contains("6AE1") {
                                        print("Already patched")
                                        return
                                    }
                                    
                                    cls.isa = (cls.isa & 0x00000000ffffffff) | 0x800D6AE100000000
                                    cls.superclass = (cls.superclass & 0x00000000ffffffff) | 0xC00DB5AB00000000
                                    
                                    print(String(format: "0x%02llX", cls.isa))
                                    print(String(format: "0x%02llX", cls.superclass))
                                    
                                    /*
                                     0x4010000000000002
                                     0x00
                                     0xC048
                                     */
                                    handle.seek(toFileOffset: UInt64(clsoff & 0x0000000fffffffff))
                                    
                                    fwrite(&cls, MemoryLayout.size(ofValue: cls), 1, handle)
                                    
                                    handle.seek(toFileOffset: UInt64(clsoff & 0x0000000fffffffff))
                                    
                                    print(handle.readData(ofLength: MemoryLayout<objc_class>.size)
                                        .assumingMemoryBound(to: objc_class.self)
                                        .pointee)
                                    
                                }
                            }*/

                            
                            if sectName.hasPrefix("__objc_data") {

                                let classes = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: Int(section.size))
                                    .assumingMemoryBound(to: objc_class.self)
                                                    
                                UnsafeBufferPointer(start: classes, count: Int(section.size) / MemoryLayout<objc_class>.size).enumerated().forEach { index, cls in
                                    
                                    var cls = cls
                                    let clsoff = UInt64(slice.offset.bigEndian) + UInt64(section.offset) + UInt64(index*MemoryLayout<objc_class>.size)
                                                                                            
                                    print("--- MAIN CLASS ----")
                                    print(String(format: "0x%02llX", cls.isa))
                                    print(String(format: "0x%02llX", cls.superclass))
                                    print(String(format: "0x%02llX", cls.cache))
                                    print(String(format: "0x%02llX", cls.vtable))
                                    print(String(format: "0x%02llX", cls.data))
                                    
                                    cls.isa = cls.isa | 0x800D6AE100000000
                                    cls.superclass = cls.superclass | 0xC00DB5AB00000000
                                    /*
                                     0x4010000000000002
                                     0x00
                                     0xC048
                                     */
                                    handle.seek(toFileOffset: UInt64(clsoff & 0x0000000fffffffff))
                                    
                                    fwrite(&cls, MemoryLayout.size(ofValue: cls), 1, handle)
                                    
                                    handle.seek(toFileOffset: UInt64(clsoff & 0x0000000fffffffff))
                                    
                                    print(handle.readData(ofLength: MemoryLayout<objc_class>.size)
                                        .assumingMemoryBound(to: objc_class.self)
                                        .pointee)
                                    
                                    struct class_ro_t {
                                        var flags: UInt32
                                        var instanceStart: UInt32
                                        var instanceSize: UInt32
                                        #if arch(arm64) || arch(x86_64)
                                        var reserved: UInt32
                                        #endif
                                        var ivarLayoutOrNonMetaclass: UInt64
                                        var name: UInt64
                                        var baseMethodList: UInt64
                                        var baseProtocols: UInt64
                                        var ivars: UInt64
                                        var weakIvarLayout: UInt64
                                        var baseProperties: UInt64
                                    }
                                    
                                    // MARK: CLS DATA (ro_t)
                                    
                                    var data = handle
                                        .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(cls.data & 0x0000000fffffffff))
                                        .readData(ofLength: MemoryLayout<class_ro_t>.size)
                                        .assumingMemoryBound(to: class_ro_t.self)
                                        .pointee
                                    
                                    print(data)
                                    print(String(format: "0x%02llX", data.baseMethodList))
                                    
                                    if data.baseMethodList != 0 {
                                        data.baseMethodList = data.baseMethodList | 0x8005c31000000000
                                    }

                                    handle.seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(cls.data & 0x0000000fffffffff))
                                    
                                    fwrite(&data, MemoryLayout.size(ofValue: data), 1, handle)
                                    
                                    print(String(cString: handle
                                        .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(data.name & 0x0000000fffffffff))
                                        .readData(ofLength: 1024)
                                        .assumingMemoryBound(to: CChar.self)))
                                    
                                    // 0x8045c31000000000
                                }
                            }

                            if sectName.hasPrefix("__cfstring") {
                                let strings = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: Int(section.size))
                                    .assumingMemoryBound(to: _cfstring.self)
                                
                                UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<_cfstring>.size).enumerated().forEach { index, string in
                                    
                                    var string = string
                                    let stringoff = UInt64(slice.offset.bigEndian) + UInt64(section.offset) + UInt64(index*MemoryLayout<_cfstring>.size)
                                    
                                    print("cfstr ISA", String(format: "0x%02llX", string.isa))
                                    // 0xc0156ae100000001
                                    
                                    if cfStringISA == 0 && (string.isa & 0x0000000fffffffff) > 100 {
                                        print("Found cfstr isa", String(format: "0x%02llX", string.isa))
                                        cfStringISA = string.isa
                                    }
                                    
                                    let strValue = handle
                                        .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(UInt(bitPattern: string.str) & 0x0000000fffffffff))
                                        .readData(ofLength: 0x4000)
                                        .assumingMemoryBound(to: CChar.self)
                                    
                                    print(String(cString: strValue))
                                                                        
                                    string.isa = string.isa | 0xc0156ae100000000
                                    
                                    print("cfstr ISA after", String(format: "0x%02llX", string.isa))
                                    
                                    handle.seek(toFileOffset: stringoff)
                                    
                                    fwrite(&string, MemoryLayout.size(ofValue: string), 1, handle)
                                    
                                }
                            }
                            
                            if sectName.hasPrefix("__data") {
                                let strings = handle
                                    .seek(toFileOffset: UInt64(slice.offset.bigEndian) + UInt64(section.offset))
                                    .readData(ofLength: Int(section.size))
                                    .assumingMemoryBound(to: UInt64.self)
                                
                                UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<UInt64>.size).enumerated().forEach { index, string in
                                    
                                    let string = string
                                    let stringoff = UInt64(slice.offset.bigEndian) + UInt64(section.offset) + UInt64(index*MemoryLayout<UInt64>.size)
                                    print(String(format: "current str isa: 0x%02llX", cfStringISA), String(format: "hikari str: 0x%02llX", string), String(format: "hikari stroff: 0x%02llX", UInt64(section.offset) + UInt64(index*MemoryLayout<UInt64>.size)))
                                    
                                    if string == cfStringISA && cfStringISA != 0x00 && string != 0x00 {
                                        print("Found cfString header!!!", String(format: "hikari str: 0x%02llX", string))
                                        
                                        var newISA = string | 0xc0156ae100000000
                                        
                                        print("cfstr ISA after", String(format: "0x%02llX", newISA))
                                        
                                        handle.seek(toFileOffset: stringoff)
                                        
                                        fwrite(&newISA, MemoryLayout.size(ofValue: newISA), 1, handle)
                                    }
                                    
                                }
                            }
                        }
                    }
                    
                    #if DEBUG
                    if cmd.cmd == LC_VERSION_MIN_IPHONEOS {
                        
                        handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                            .write(LC_VERSION_MIN_MACOSX)
                        
                        let dyldCmdPtr = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                            .readData(ofLength: MemoryLayout<version_min_command>.size)
                            .assumingMemoryBound(to: version_min_command.self)

                        defer { dyldCmdPtr.deallocate() }
                        
                        let dyldCmd = dyldCmdPtr.pointee
                        
                        print(dyldCmd, dyldCmd.cmd == LC_VERSION_MIN_MACOSX)
                    } else if cmd.cmd == LC_BUILD_VERSION {
                        var buildCmdPtr = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                            .readData(ofLength: MemoryLayout<build_version_command>.size)
                            .assumingMemoryBound(to: build_version_command.self)

                        defer { buildCmdPtr.deallocate() }
                        
                        let buildCmd = buildCmdPtr.pointee
                        
                        print(buildCmd)
                                                
                        handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index + 0x8)
                            .write(UInt32(6))
                        
                        let buildCmdPtr2 = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                            .readData(ofLength: MemoryLayout<build_version_command>.size)
                            .assumingMemoryBound(to: build_version_command.self)

                        defer { buildCmdPtr2.deallocate() }
                        
                        let buildCmd2 = buildCmdPtr2.pointee
                        
                        print(buildCmd2)
                    } else if cmd.cmd == LC_LOAD_DYLIB {
                        let loadDylibCmdPtr = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index)
                            .readData(ofLength: MemoryLayout<dylib_command>.size)
                            .assumingMemoryBound(to: dylib_command.self)

                        defer { loadDylibCmdPtr.deallocate() }
                        
                        let loadDylibCmd = loadDylibCmdPtr.pointee
                        
                        let strData = handle
                            .seek(toFileOffset: UInt64(slice.offset.bigEndian) + index + UInt64(loadDylibCmd.dylib.name.offset))
                            .readData(ofLength: 0x4000)
                            .assumingMemoryBound(to: CChar.self)
                                                
                        if String(cString: strData).contains("CydiaSubstrate") || String(cString: strData).contains("libsubstrate") {
                            fwrite(
                                substrateMacPath,
                                substrateMacPath.count + 1, 1,
                                handle.seek(toFileOffset: UInt64(slice.offset.bigEndian) + index + UInt64(loadDylibCmd.dylib.name.offset))
                            )
                        }
                        
                        if String(cString: strData) == "/System/Library/Frameworks/UIKit.framework/UIKit" {
//                            fwrite(
//                                substrateMacPath,
//                                substrateMacPath.count + 1, 1,
//                                handle.seek(toFileOffset: UInt64(slice.offset.bigEndian) + index + UInt64(loadDylibCmd.dylib.name.offset))
//                            )
                        }
                        
                        print(String(cString: strData))
                        
                        strData.deallocate()
                    }
                    #endif
                    
                    index += UInt64(cmd.cmdsize)
                    
                }
            }
        }
    }
}

patchArch(file)

print(file)

#if DEBUG


let handle = dlopen(file, RTLD_LAZY)

//print(handle, String(cString: dlerror()))

try FileManager.default.removeItem(atPath: file)
#endif
