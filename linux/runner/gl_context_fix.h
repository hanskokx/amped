#ifndef RUNNER_GL_CONTEXT_FIX_H_
#define RUNNER_GL_CONTEXT_FIX_H_

// Works around a Flutter engine bug that kills the app on X11 with
// "BadAccess ... (GLX) minor_code 26" once it opens its windows.
//
// GTK draws with a GLX context, which stays current on the main thread, and
// the engine sets up each view's OpenGL compositor on that thread with EGL.
// A thread may only have a context of one of the two current: the engine
// doesn't release GTK's first, and for every view but the implicit one it
// leaves its own current afterwards, so GTK's next draw fails. Amped's windows
// are all such views.
//
// This releases the contexts around the two places that happens. It follows
// https://github.com/flutter/flutter/pull/193530 and can be removed once the
// Flutter release in use includes that fix.
//
// Call after creating the first FlView and before any other.
void gl_context_fix_install();

#endif  // RUNNER_GL_CONTEXT_FIX_H_
