// Loaded into both probe processes with DYLD_INSERT_LIBRARIES (run.sh). Every keychain and trust
// settings entry point the project's code could reach is interposed: a call prints its name and
// aborts the process, so a run that finishes is a run that made none of these calls.
#include <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { const void *replacement; const void *replacee; } \
    _interpose_##_replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&_replacement, (const void *)(unsigned long)&_replacee };

static void refuse(const char *name) {
    char line[160];
    int n = snprintf(line, sizeof line, "KEYCHAIN GUARD: %s was called; aborting the probe\n", name);
    write(2, line, n > 0 ? (size_t)n : 0);
    abort();
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static OSStatus guard_SecItemAdd(CFDictionaryRef a, CFTypeRef *r) { refuse("SecItemAdd"); return errSecNotAvailable; }
static OSStatus guard_SecItemUpdate(CFDictionaryRef a, CFDictionaryRef b) { refuse("SecItemUpdate"); return errSecNotAvailable; }
static OSStatus guard_SecItemDelete(CFDictionaryRef a) { refuse("SecItemDelete"); return errSecNotAvailable; }
static OSStatus guard_SecItemCopyMatching(CFDictionaryRef a, CFTypeRef *r) { refuse("SecItemCopyMatching"); return errSecNotAvailable; }
static OSStatus guard_SecTrustSettingsSetTrustSettings(SecCertificateRef c, SecTrustSettingsDomain d, CFTypeRef t) {
    refuse("SecTrustSettingsSetTrustSettings"); return errSecNotAvailable;
}
static OSStatus guard_SecTrustSettingsRemoveTrustSettings(SecCertificateRef c, SecTrustSettingsDomain d) {
    refuse("SecTrustSettingsRemoveTrustSettings"); return errSecNotAvailable;
}
static OSStatus guard_SecCertificateAddToKeychain(SecCertificateRef c, SecKeychainRef k) {
    refuse("SecCertificateAddToKeychain"); return errSecNotAvailable;
}
static OSStatus guard_SecKeychainItemDelete(SecKeychainItemRef i) { refuse("SecKeychainItemDelete"); return errSecNotAvailable; }
static OSStatus guard_SecKeychainAddGenericPassword(SecKeychainRef k, UInt32 a, const char *b, UInt32 c, const char *d,
                                                    UInt32 e, const void *f, SecKeychainItemRef *g) {
    refuse("SecKeychainAddGenericPassword"); return errSecNotAvailable;
}

DYLD_INTERPOSE(guard_SecItemAdd, SecItemAdd)
DYLD_INTERPOSE(guard_SecItemUpdate, SecItemUpdate)
DYLD_INTERPOSE(guard_SecItemDelete, SecItemDelete)
DYLD_INTERPOSE(guard_SecItemCopyMatching, SecItemCopyMatching)
DYLD_INTERPOSE(guard_SecTrustSettingsSetTrustSettings, SecTrustSettingsSetTrustSettings)
DYLD_INTERPOSE(guard_SecTrustSettingsRemoveTrustSettings, SecTrustSettingsRemoveTrustSettings)
DYLD_INTERPOSE(guard_SecCertificateAddToKeychain, SecCertificateAddToKeychain)
DYLD_INTERPOSE(guard_SecKeychainItemDelete, SecKeychainItemDelete)
DYLD_INTERPOSE(guard_SecKeychainAddGenericPassword, SecKeychainAddGenericPassword)
#pragma clang diagnostic pop

__attribute__((constructor)) static void announce(void) {
    const char line[] = "KEYCHAIN GUARD: loaded (SecItem*, SecTrustSettings*, SecKeychain* writes abort)\n";
    write(2, line, sizeof line - 1);
}
