#include <ctype.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef OG_PROGRAM
#error OG_PROGRAM must name the packaged executable
#endif
#ifndef OG_STATIC_PREFIX
#define OG_STATIC_PREFIX ""
#endif

typedef const char *(*libroot_prefix_function)(void);
typedef const char *(*roothide_jbroot_function)(const char *);

static char resolved[PATH_MAX];

static int join_path(char output[PATH_MAX], const char *prefix, const char *suffix) {
    int length = snprintf(output, PATH_MAX, "%s%s", prefix, suffix);
    return length > 0 && length < PATH_MAX;
}

/// Copy `prefix` into `resolved` without trailing slashes; NULL unless it is
/// an absolute path that fits.
static const char *keep_prefix(const char *prefix) {
    if (!prefix || prefix[0] != '/') return NULL;
    size_t length = strlen(prefix);
    while (length > 1 && prefix[length - 1] == '/') length--;
    if (length >= sizeof(resolved)) return NULL;
    memmove(resolved, prefix, length);
    resolved[length] = 0;
    return resolved;
}

static const char *prefix_from_libroot(void) {
    static const char *const libraries[] = {
        "@executable_path/../lib/libroot.dylib",
        "@executable_path/.jbroot/usr/lib/libroot.dylib",
        "/var/jb/usr/lib/libroot.dylib",
    };
    for (size_t index = 0; index < sizeof(libraries) / sizeof(libraries[0]); index++) {
        void *handle = dlopen(libraries[index], RTLD_NOW | RTLD_LOCAL);
        if (!handle) continue;
        libroot_prefix_function get_prefix =
            (libroot_prefix_function)dlsym(handle, "libroot_get_jbroot_prefix");
        const char *prefix = keep_prefix(get_prefix ? get_prefix() : NULL);
        dlclose(handle);
        if (prefix) return prefix;
    }
    return NULL;
}

/// RootHide bootstraps ship libroothide rather than libroot.
static const char *prefix_from_libroothide(void) {
    static const char *const libraries[] = {
        "@executable_path/.jbroot/usr/lib/libroothide.dylib",
        "@executable_path/../lib/libroothide.dylib",
    };
    for (size_t index = 0; index < sizeof(libraries) / sizeof(libraries[0]); index++) {
        void *handle = dlopen(libraries[index], RTLD_NOW | RTLD_LOCAL);
        if (!handle) continue;
        roothide_jbroot_function jbroot = (roothide_jbroot_function)dlsym(handle, "jbroot");
        const char *prefix = keep_prefix(jbroot ? jbroot("/") : NULL);
        dlclose(handle);
        if (prefix) return prefix;
    }
    return NULL;
}

/// RootHide links `.jbroot` beside every bootstrap directory, so the one next
/// to this launcher names the root it was installed into.
static const char *prefix_from_executable_link(void) {
    char executable[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) != 0) return NULL;
    char *slash = strrchr(executable, '/');
    if (!slash) return NULL;
    *slash = 0;
    char link[PATH_MAX], target[PATH_MAX];
    if (!join_path(link, executable, "/.jbroot") || !realpath(link, target)) return NULL;
    return keep_prefix(target);
}

/// RootHide names its root `.jbroot-<16 hex digits>`, the last byte being the
/// XOR of the seven before it — the check that tells a root from a lookalike.
static int roothide_root_name(const char *name) {
    static const char prefix[] = ".jbroot-";
    if (strncmp(name, prefix, sizeof(prefix) - 1) != 0) return 0;
    const char *digits = name + sizeof(prefix) - 1;
    if (strlen(digits) != 16) return 0;
    for (int index = 0; index < 16; index++) {
        if (!isxdigit((unsigned char)digits[index])) return 0;
    }
    uint64_t value = strtoull(digits, NULL, 16);
    uint8_t check = 0;
    for (int shift = 8; shift < 64; shift += 8) check ^= (uint8_t)(value >> shift);
    return check == (uint8_t)value;
}

/// The one RootHide root where RootHide puts it; none when there are several,
/// since nothing here can tell which is in use.
static const char *prefix_from_filesystem(void) {
    static const char parent[] = "/private/var/containers/Bundle/Application";
    if (access("/var/jb", F_OK) == 0) return NULL;
    DIR *directory = opendir(parent);
    if (!directory) return NULL;
    char found[PATH_MAX] = "";
    int count = 0;
    struct dirent *entry;
    while ((entry = readdir(directory))) {
        if (!roothide_root_name(entry->d_name)) continue;
        char path[PATH_MAX];
        struct stat info;
        if (!join_path(path, parent, "/") || strlcat(path, entry->d_name, sizeof(path)) >= sizeof(path) ||
            lstat(path, &info) != 0 || !S_ISDIR(info.st_mode)) continue;
        if (count++ == 0) memcpy(found, path, sizeof(found));
    }
    closedir(directory);
    return count == 1 ? keep_prefix(found) : NULL;
}

/// Same order as icli's bootstrap resolution: libroot, libroothide, the
/// `.jbroot` link beside the executable, then RootHide's root on disk.
static const char *bootstrap_prefix(void) {
    const char *configured = OG_STATIC_PREFIX;
    if (configured[0]) return configured;
    const char *prefix = prefix_from_libroot();
    if (!prefix) prefix = prefix_from_libroothide();
    if (!prefix) prefix = prefix_from_executable_link();
    if (!prefix) prefix = prefix_from_filesystem();
    return prefix;
}

static void configure_environment(const char *prefix) {
    const char *current = getenv("PATH");
    char *path = NULL;
    if (asprintf(&path, "%s/usr/local/bin:%s/usr/bin:%s/bin:%s/usr/sbin:%s/sbin%s%s",
                 prefix, prefix, prefix, prefix, prefix,
                 current && current[0] ? ":" : "", current && current[0] ? current : "") >= 0) {
        setenv("PATH", path, 1);
        free(path);
    }
    const char *shell = getenv("SHELL");
    char candidate[PATH_MAX];
    if (shell && (strncmp(shell, "/bin/", 5) == 0 || strncmp(shell, "/usr/bin/", 9) == 0) &&
        join_path(candidate, prefix, shell)) setenv("SHELL", candidate, 1);
    if (!getenv("SSL_CERT_FILE")) {
        const char *certificates[] = {"/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt"};
        for (size_t index = 0; index < 2; index++) {
            if (join_path(candidate, prefix, certificates[index]) && access(candidate, R_OK) == 0) {
                setenv("SSL_CERT_FILE", candidate, 1);
                break;
            }
        }
    }
    if (!getenv("BROWSER") && join_path(candidate, prefix, "/usr/bin/uiopen") &&
        access(candidate, X_OK) == 0) setenv("BROWSER", candidate, 1);
}

int main(int argc, char **argv) {
    (void)argc;
    const char *prefix = bootstrap_prefix();
    if (!prefix) {
        fprintf(stderr, "%s: cannot find the jailbreak bootstrap\n", OG_PROGRAM);
        return 127;
    }
    configure_environment(prefix);
    char executable[PATH_MAX];
    if (!join_path(executable, prefix, "/usr/libexec/" OG_PROGRAM "/" OG_PROGRAM)) return 127;
    argv[0] = executable;
    execv(executable, argv);
    int error = errno;
    fprintf(stderr, "%s: cannot execute %s: %s\n", OG_PROGRAM, executable, strerror(error));
    return error == ENOENT ? 127 : 126;
}
