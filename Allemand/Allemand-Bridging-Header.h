//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#if __arm64e__
#include <ptrauth.h>
#endif
#include <stdio.h>

#if __arm64e__
static const uint16_t methodListPointerDiscriminator = 0xC310;

#define ISA_SIGNING_DISCRIMINATOR 0x6AE1
#define ISA_SIGNING_DISCRIMINATOR_CLASS_SUPERCLASS 0xB5AB

void* sign_methodlist(void* cls) {
    return ptrauth_sign_unauthenticated(cls, ptrauth_key_method_list_pointer, ptrauth_blend_discriminator(cls, methodListPointerDiscriminator));
}

void* sign_isa(void* cls) {
    return ptrauth_sign_unauthenticated(cls, ptrauth_key_process_independent_data, ptrauth_blend_discriminator(cls, ISA_SIGNING_DISCRIMINATOR));
}

void* sign_superclass(void* cls) {
    return ptrauth_sign_unauthenticated(ptrauth_strip(*(void**)(cls + 8), ptrauth_key_process_independent_data), ptrauth_key_process_independent_data, ptrauth_blend_discriminator(ptrauth_strip((cls + 8), ptrauth_key_process_independent_data), ISA_SIGNING_DISCRIMINATOR));
    __asm__("xpacd x0");
    __asm__("add x0, x0, #8"); // class + 8
    __asm__("ldr x1, [x0]"); // superclass
    __asm__("xpacd x1");
    __asm__("movk x1, #0xB5AB, lsl #48");
    __asm__("pacda x1, x0");
    __asm__("mov x0, x1");
    __asm__("ret");
}

void* auth_superclass(void* cls) {
    __asm__ volatile("add x0, x0, #8"); // class + 8
    __asm__ volatile("ldr x1, [x0]"); // superclass
    __asm__ volatile("movk x0, #0xB5AB, lsl #48");
    __asm__ volatile("autda x1, x0");
    __asm__ volatile("mov x0, x1");
    __asm__ volatile("ret");
}
#endif
