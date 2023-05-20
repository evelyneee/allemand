//
//  unused.swift
//  Allemand
//
//  Created by charl❤️‍🔥 on 2023-05-20.
//

import Foundation

#if false

public func patchLiveHeader(
    image machHeaderPointer: UnsafeRawPointer
) {
    
    var machHeaderPointer = machHeaderPointer
    
    if machHeaderPointer.assumingMemoryBound(to: mach_header_64.self).pointee.magic == FAT_CIGAM {
        // we have a fat binary
        // get our current cpu subtype
        let nslices = machHeaderPointer
            .advanced(by: 0x4)
            .assumingMemoryBound(to: UInt32.self)
            .pointee.bigEndian
        
        for i in 0..<nslices {
            let slice = machHeaderPointer
                .advanced(by: 8 + (Int(i) * 20))
                .assumingMemoryBound(to: fat_arch.self)
                .pointee
            #if arch(arm64)
            if slice.cputype.bigEndian == CPU_TYPE_ARM64 { // hope that there's no arm64e subtype
                machHeaderPointer = machHeaderPointer.advanced(by: Int(slice.offset.bigEndian))
            }
            #else
            if slice.cputype.bigEndian == CPU_TYPE_X86_64 {
                machHeaderPointer = machHeaderPointer.advanced(by: Int(slice.offset.bigEndian))
            }
            #endif
        }
    }
    
    let machHeader = machHeaderPointer.assumingMemoryBound(to: mach_header_64.self).pointee
        
    // Read the load commands
    var command = machHeaderPointer.advanced(by: MemoryLayout<mach_header_64>.size)
    var commandIt = command;

    // First iteration: Get symtab pointer
    
    // Second iteration: Resolve offsets by segments
    for _ in 0..<machHeader.ncmds {
        let load_command = command.assumingMemoryBound(to: load_command.self).pointee
        
        if load_command.cmd == LC_SEGMENT_64 {
            let segment_command = command.assumingMemoryBound(to: segment_command_64.self).pointee
            
            let segnameString = withUnsafePointer(to: segment_command.segname) {
                $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                    String(cString: $0)
                }
            }
            
            UnsafeBufferPointer(start: command.advanced(by: MemoryLayout<segment_command_64>.stride).assumingMemoryBound(to: section_64.self), count: Int(segment_command.nsects)).enumerated().forEach { idx, section in
                let sectName = withUnsafePointer(to: section.sectname) {
                    $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                        String(cString: $0)
                    }
                }
                
                print(sectName)
                                    
                if sectName.hasPrefix("__objc_data") {
                    
                    struct objc_class {
                        var isa: UnsafeMutableRawPointer
                        var superclass: UnsafeMutableRawPointer
                        var cache: UInt64
                        var vtable: UInt64
                        var data: UInt64
                    }

                    let classes = machHeaderPointer
                        .advanced(by: Int(section.offset))
                        .assumingMemoryBound(to: objc_class.self)
                                        
                    UnsafeBufferPointer(start: classes, count: Int(section.size) / MemoryLayout<objc_class>.size).enumerated().forEach { index, cls in
                        
                        var cls = cls
                        let clsoff = UInt64(section.offset) + UInt64(index*MemoryLayout<objc_class>.size)
                        let classptr = UnsafeMutableRawPointer(mutating: machHeaderPointer.advanced(by: Int(clsoff & 0x0000000fffffffff)))
                                                                                
                        print("--- MAIN CLASS ----")
                        print(cls.isa)
                        print(cls.superclass)
                        print(String(format: "0x%02llX", cls.cache))
                        print(String(format: "0x%02llX", cls.vtable))
                        print(String(format: "0x%02llX", cls.data))
                        
                        //cls.isa = sign_isa(classptr)
                        //cls.superclass = sign_superclass(classptr)
                        
                        print("--- MAIN CLASS PATCHED ----")
                        print(cls.isa)
                        print(cls.superclass)
                        print(String(format: "0x%02llX", cls.cache))
                        print(String(format: "0x%02llX", cls.vtable))
                        print(String(format: "0x%02llX", cls.data))
                        /*
                         0x4010000000000002
                         0x00
                         0xC048
                         */
                                                
                        print(mach_vm_protect(mach_task_self_, mach_vm_address_t(UInt(bitPattern: classptr)), 128, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY))
                        classptr.storeBytes(of: cls, as: objc_class.self)
                        print(mach_vm_protect(mach_task_self_, mach_vm_address_t(UInt(bitPattern: classptr)), 128, 0, VM_PROT_READ | VM_PROT_EXECUTE))
                                   
                        
                        struct class_ro_t {
                            let flags: UInt32
                            let instanceStart: UInt32
                            let instanceSize: UInt32
                            let reserved: UInt32
                            let ivarLayout: UnsafePointer<UInt8>?
                            let name: Int
                            var baseMethodList: UnsafeMutableRawPointer?
                            let baseProtocols: UnsafeRawPointer?
                            let ivars: UnsafeRawPointer?
                            let weakIvarLayout: UnsafePointer<UInt8>?
                            let baseProperties: UnsafePointer<UnsafePointer<objc_property_t>?>?
                        }
                        
                        // MARK: CLS DATA (ro_t)
                        
                        var data = machHeaderPointer
                            .advanced(by: Int(cls.data & 0x0000000fffffffff))
                            .assumingMemoryBound(to: class_ro_t.self)
                            .pointee
                        
                        print(data)
                        
                        if let list = data.baseMethodList {
                            //data.baseMethodList = sign_methodlist(list)
                        }
                        
                        
                        let classroptr = UnsafeMutableRawPointer(bitPattern: Int(cls.data & 0x0000000fffffffff))
                        
                        print(mach_vm_protect(mach_task_self_, mach_vm_address_t(UInt(bitPattern: classroptr)), 128, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY))
                        classroptr?.storeBytes(of: data, as: class_ro_t.self)
                                                
//                        print(String(cString: machHeaderPointer
//                            .advanced(by: Int(data.name & 0x0000000fffffffff))
//                            .assumingMemoryBound(to: CChar.self)))
                        
                        // 0x8045c31000000000
                    }
                }
                
                if sectName.hasPrefix("__cfstring") {
                    let strings = machHeaderPointer
                        .advanced(by: Int(section.offset))
                        .assumingMemoryBound(to: _cfstring.self)
                    
                    UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<_cfstring>.size).enumerated().forEach { index, string in
                        
                        var string = string
                        let stringoff = UInt64(section.offset) + UInt64(index*MemoryLayout<_cfstring>.size)
                        
                        print(string)
                        // 0xc0156ae100000001
                        
                        //string.isa = string.isa | 0xc0156ae100000000
                        
                        let ptr = UnsafeMutableRawPointer(mutating: machHeaderPointer.advanced(by: Int(stringoff)))
                        print(mach_vm_protect(mach_task_self_, mach_vm_address_t(UInt(bitPattern: ptr)), 128, 0, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY))
                        ptr.storeBytes(of: string, as: _cfstring.self)
                        print(mach_vm_protect(mach_task_self_, mach_vm_address_t(UInt(bitPattern: ptr)), 128, 0, VM_PROT_READ | VM_PROT_EXECUTE))
                    }
                }
            }

            
        }
        
        command = command.advanced(by: Int(load_command.cmdsize))
    }
}
#endif

/*
 thin slice code
 {
     print("thin slices unsupported")
     exit(1)
     let header = machHeaderPointer.assumingMemoryBound(to: mach_header_64.self).pointee
     
     print("ORIG:", String(format: "%02X", header.cpusubtype.bigEndian))
             
     var index: UInt64 = 0x20
     
     for _ in 0..<header.ncmds {
         let cmdPtr = handle
             .seek(toFileOffset: index)
             .readData(ofLength: MemoryLayout<load_command>.size)
             .assumingMemoryBound(to: load_command.self)
         
         defer { cmdPtr.deallocate() }
         
         let cmd = cmdPtr.pointee
         
         if cmd.cmd == LC_SEGMENT_64 {
             let segmentCmd = handle
                 .seek(toFileOffset: index)
                 .readData(ofLength: MemoryLayout<segment_command_64>.size)
                 .assumingMemoryBound(to: segment_command_64.self)
                 .pointee
             
             
             let segnameString = withUnsafePointer(to: segmentCmd.segname) {
                 $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                     String(cString: $0)
                 }
             }
             
             let sections = handle
                 .seek(toFileOffset: index + UInt64(MemoryLayout<segment_command_64>.stride))
                 .readData(ofLength: Int(segmentCmd.vmsize))
                 .assumingMemoryBound(to: section_64.self)
             
             UnsafeBufferPointer(start: sections, count: Int(segmentCmd.nsects)).enumerated().forEach { idx, section in
                 let sectName = withUnsafePointer(to: section.sectname) {
                     $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                         String(cString: $0)
                     }
                 }
                 
                 print(sectName)
                     
                 #if false
                 if sectName.hasPrefix("__objc_selrefs") {
                     #if false
                     _ = withUnsafePointer(to: section.sectname) {
                         $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                             strcpy(UnsafeMutableRawPointer.init(mutating: $0), ("__objc_selreef" as NSString).utf8String!)
                         }
                     }
                     
                     var section = section
                     section.sectname.11 = 0x43
                     
                     print(withUnsafePointer(to: section.sectname) {
                         $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout.size(ofValue: $0)) {
                             String(cString: $0)
                         }
                     })
                     
                     handle.seek(toFileOffset: index + UInt64(MemoryLayout<segment_command_64>.stride) + UInt64(idx*MemoryLayout<section_64>.size))
                     
                     fwrite(&section, MemoryLayout.size(ofValue: section), 1, handle)
                     
                     handle.seek(toFileOffset: index + UInt64(MemoryLayout<segment_command_64>.stride) + UInt64(idx*MemoryLayout<section_64>.size))

                     print(String(cString: handle.readData(ofLength: 1024).assumingMemoryBound(to: CChar.self)))
                     #endif
                     
                     let strings = handle
                         .seek(toFileOffset: UInt64(section.offset))
                         .readData(ofLength: Int(section.size))
                         .assumingMemoryBound(to: UInt64.self)
                     
                     UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<UInt64>.size).enumerated().forEach { index, sel in
                         
                         var sel = sel
                         let seloff = UInt64(section.offset) + UInt64(index*MemoryLayout<UInt64>.size)
                         
                         print(String(format: "sel: 0x%02llX", sel))
                         
                         handle.seek(toFileOffset: seloff)
                         print(String(format: "selbefore: 0x%02llX", handle.readData(ofLength: 8).assumingMemoryBound(to: UInt64.self).pointee))
                         var newSel = (sel & 0x0000000fffffffff)
                         handle.seek(toFileOffset: seloff)
                         //fwrite(&newSel, MemoryLayout.size(ofValue: newSel), 1, handle)
                         
                         handle.seek(toFileOffset: seloff)
                         
                         print(String(format: "selnew: 0x%02llX", handle.readData(ofLength: 8).assumingMemoryBound(to: UInt64.self).pointee))
                         
                     }
                 }
                 #endif
                 
                 if sectName.hasPrefix("__objc_data") {
                     struct objc_class {
                         var isa: UInt64
                         var superclass: UInt64
                         var cache: UInt64
                         var vtable: UInt64
                         var data: UInt64
                     }

                     let classes = handle
                         .seek(toFileOffset: UInt64(section.offset))
                         .readData(ofLength: Int(section.size))
                         .assumingMemoryBound(to: objc_class.self)
                                         
                     UnsafeBufferPointer(start: classes, count: Int(section.size) / MemoryLayout<objc_class>.size).enumerated().forEach { index, cls in
                         
                         var cls = cls
                         let clsoff = UInt64(section.offset) + UInt64(index*MemoryLayout<objc_class>.size)
                                                                                 
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
                             var flags: Int32
                             var ivar_base_start: Int32
                             var ivar_base_size: Int32
                             var reserved: Int32
                             var ivar_lyt: UnsafeRawPointer
                             var name: UInt64
                             var base_meths: UInt64
                             var base_prots: UnsafeRawPointer
                             var ivars: UnsafeRawPointer
                             var weak_ivar_lyt: UnsafeRawPointer
                             var base_props: UnsafeRawPointer
                         }
                         
                         // MARK: CLS DATA (ro_t)
                         
                         var data = handle
                             .seek(toFileOffset: UInt64(cls.data & 0x0000000fffffffff))
                             .readData(ofLength: MemoryLayout<class_ro_t>.size)
                             .assumingMemoryBound(to: class_ro_t.self)
                             .pointee
                         
                         print(data)
                         print(String(format: "0x%02llX", data.base_meths))
                         
                         data.base_meths = data.base_meths | 0x8005c31000000000
                         
                         handle.seek(toFileOffset: UInt64(cls.data & 0x0000000fffffffff))
                         
                         fwrite(&data, MemoryLayout.size(ofValue: data), 1, handle)
                         
                         print(String(cString: handle
                             .seek(toFileOffset: UInt64(data.name & 0x0000000fffffffff))
                             .readData(ofLength: 1024)
                             .assumingMemoryBound(to: CChar.self)))
                         
                         // 0x8045c31000000000
                     }
                 }
                 
                 if sectName.hasPrefix("__cfstring") {
                     let strings = handle
                         .seek(toFileOffset: UInt64(section.offset))
                         .readData(ofLength: Int(section.size))
                         .assumingMemoryBound(to: _cfstring.self)
                     
                     UnsafeBufferPointer(start: strings, count: Int(section.size) / MemoryLayout<_cfstring>.size).enumerated().forEach { index, string in
                         
                         var string = string
                         let stringoff = UInt64(section.offset) + UInt64(index*MemoryLayout<_cfstring>.size)
                         
                         print(string)
                         // 0xc0156ae100000001
                         
                         string.isa = string.isa | 0xC0156AE100000000
                         
                         handle.seek(toFileOffset: stringoff)
                         
                         fwrite(&string, MemoryLayout.size(ofValue: string), 1, handle)
                         
                     }
                 }
             }
             
         }
                  
         if cmd.cmd == LC_VERSION_MIN_IPHONEOS {
             
             handle
                 .seek(toFileOffset: index)
                 .write(LC_VERSION_MIN_MACOSX)
             
             let dyldCmdPtr = handle
                 .seek(toFileOffset: index)
                 .readData(ofLength: MemoryLayout<version_min_command>.size)
                 .assumingMemoryBound(to: version_min_command.self)

             defer { dyldCmdPtr.deallocate() }
             
             let dyldCmd = dyldCmdPtr.pointee
             
             print(dyldCmd, dyldCmd.cmd == LC_VERSION_MIN_MACOSX)
         } else if cmd.cmd == LC_BUILD_VERSION {
             var buildCmdPtr = handle
                 .seek(toFileOffset: index)
                 .readData(ofLength: MemoryLayout<build_version_command>.size)
                 .assumingMemoryBound(to: build_version_command.self)

             defer { buildCmdPtr.deallocate() }
             
             let buildCmd = buildCmdPtr.pointee
             
             print(buildCmd)
                                     
             handle
                 .seek(toFileOffset: index + 0x8)
                 .write(UInt32(6))
             
             let buildCmdPtr2 = handle
                 .seek(toFileOffset: index)
                 .readData(ofLength: MemoryLayout<build_version_command>.size)
                 .assumingMemoryBound(to: build_version_command.self)

             defer { buildCmdPtr2.deallocate() }
             
             let buildCmd2 = buildCmdPtr2.pointee
             
             print(buildCmd2)
         } else if cmd.cmd == LC_LOAD_DYLIB {
             
             continue;
             let loadDylibCmdPtr = handle
                 .seek(toFileOffset: index)
                 .readData(ofLength: MemoryLayout<dylib_command>.size)
                 .assumingMemoryBound(to: dylib_command.self)

             defer { loadDylibCmdPtr.deallocate() }
             
             let loadDylibCmd = loadDylibCmdPtr.pointee
             
             let strData = handle
                 .seek(toFileOffset: index + UInt64(loadDylibCmd.dylib.name.offset))
                 .readData(ofLength: 0x4000)
                 .assumingMemoryBound(to: CChar.self)
                                     
             if String(cString: strData).contains("CydiaSubstrate") {
                 fwrite(
                     substrateMacPath,
                     substrateMacPath.count + 1, 1,
                     handle.seek(toFileOffset: index + UInt64(loadDylibCmd.dylib.name.offset))
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
         
         index += UInt64(cmd.cmdsize)
         
     }
 }
 */
