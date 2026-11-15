// Exposes os_proc_available_memory() to Swift. <os/proc.h> is not part of the
// Darwin module map, so a bridging header is the supported route on iOS.
#include <os/proc.h>
