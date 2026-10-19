#ifndef CLASH_C_JAVASCRIPTCORE_SHIM_H
#define CLASH_C_JAVASCRIPTCORE_SHIM_H
// The JavaScriptCore C API. On Debian/Ubuntu the headers live under
// webkitgtk-4.1, which the package configuration adds to the include path; the
// angle-include works on both that layout and Apple's framework layout.
#include <JavaScriptCore/JavaScript.h>

// `JSContextGroupSetExecutionTimeLimit` is exported by every JavaScriptCore
// that ships a `JSContextGroupRef`, but the Gtk header set omits it (it is
// declared in WebKit's own JSContextRefPrivate.h, next to the public API). So
// it is declared here, with the signature from that header, rather than the
// engine being limited to abandoning a run it cannot stop.
//
// The callback may be NULL: with none, JavaScriptCore terminates the script
// itself when the limit is reached, which is exactly what a runaway rewrite
// script needs.
#if defined(__cplusplus)
extern "C" {
#endif
JS_EXPORT void JSContextGroupSetExecutionTimeLimit(JSContextGroupRef group,
                                                   double limit,
                                                   bool (*callback)(JSContextRef, void*),
                                                   void* context);
JS_EXPORT void JSContextGroupClearExecutionTimeLimit(JSContextGroupRef group);
#if defined(__cplusplus)
}
#endif

#endif
