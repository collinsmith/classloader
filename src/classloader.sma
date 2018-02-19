#include <amxmodx>
#include <amxmisc>

#include "include/stocks/misc_stocks.inc"
#include "include/stocks/param_stocks.inc"
#include "include/stocks/path_stocks.inc"
#include "include/stocks/string_utils.inc"

#define VERSION_STRING "1.0.0"
#define COMPILE_FOR_DEBUG

static Trie: classLoaders;
#if defined COMPILE_FOR_DEBUG
static Trie: classLoaderPlugins;
#endif

public plugin_init() {
  new buildId[32];
  getBuildId(buildId, charsmax(buildId));
  register_plugin("Class Loader", buildId, "Tirant");

#if defined COMPILE_FOR_DEBUG
  registerConCmd(
      .prefix = "cl",
      .command = "loaders",
      .callback = "onPrintClassLoaders",
      .desc = "Lists all registered class loaders");
#endif
}

stock getBuildId(buildId[], len) {
  return formatex(buildId, len, "%s [%s]", VERSION_STRING, __DATE__);
}

#if defined COMPILE_FOR_DEBUG
public onPrintClassLoaders(id) {
  console_print(id, "Class Loaders:");
  
  new count;
  if (classLoaders) {
    new key[32];
    new Snapshot: keySet = TrieSnapshotCreate(classLoaderPlugins);
    count = TrieSnapshotLength(keySet);
    for (new i = 0, len; i < count; i++) {
      len = TrieSnapshotGetKey(keySet, i, key, charsmax(key));
      key[len] = EOS;

      new Array: plugins;
      TrieGetCell(classLoaderPlugins, key, plugins);
      
      new numPlugins = ArraySize(plugins);
      for (new j = 0; j < numPlugins; j++) {
        new plugin = ArrayGetCell(plugins, j);
        new filename[32];
        get_plugin(plugin, .filename = filename, .len1 = charsmax(filename));
        console_print(id, "%4s [%s]", key, filename);
      }
    }

    TrieSnapshotDestroy(keySet);
  }
  
  console_print(id, "%d class loaders registered.", count);
  return PLUGIN_HANDLED;
}
#endif

/*******************************************************************************
 * Code
 ******************************************************************************/

loadClasses(path[], bool: recursive = false) {
#if defined COMPILE_FOR_DEBUG
  logd("Loading classes in \"%s\"", path);
#endif

  new file[32];
  new dir = open_dir(path, file, charsmax(file));
  if (!dir) {
    loge("Failed to open \"%s\" (not found or unable to open)", path);
    return;
  }

  new subPath[PLATFORM_MAX_PATH], len;
  new const subPathLen = charsmax(subPath);
  len = copy(subPath, subPathLen, path);
  if (len <= subPathLen) {
    subPath[len++] = PATH_SEPARATOR;
  }

  new const pathLen = len;
  do {
    len = pathLen + copy(subPath[pathLen], subPathLen - pathLen, file);
    if (equal(file, ".") || equal(file, "..")) {
      continue;
    }

    if (dir_exists(subPath)) {
      if (recursive) {
        loadClasses(subPath, .recursive = true);
      }

      continue;
    }

    loadClass(subPath, len);
  } while (next_file(dir, file, charsmax(file)));
  close_dir(dir);
}

loadClass(path[], len) {
#if defined COMPILE_FOR_DEBUG
  assert classLoaders;
  logd("Parsing class file \"%s\"", path);
#endif

  // TODO: turn this into a file util stock
  new extension[32];
  for (new i = len - 1; i >= 0; i--) {
    if (path[i] == PATH_SEPARATOR) {
      logw("Failed to load \"%s\", no extension", path);
      return;
    } else if (path[i] == '.') {
      copy(extension, charsmax(extension), path[i + 1]);
      break;
    }
  }

  new Array: callbacks;
  new bool: keyExists = TrieGetCell(classLoaders, extension, callbacks);
  if (!keyExists) {
    logw("Failed to load \"%s\", no class loader registered for \"%s\"", path, extension);
    return;
  }

  new onLoadClass;
  new const size = ArraySize(callbacks);
  for (new i = 0; i < size; i++) {
    onLoadClass = ArrayGetCell(callbacks, i);
#if defined DEBUG_LOADERS
    logd("Forwarding to class loader %d", onLoadClass);
#endif
    ExecuteForward(onLoadClass, _, path, extension);
  }
}

/*******************************************************************************
 * Natives
 ******************************************************************************/

stock bool: operator=(value) return value > 0;

public plugin_natives() {
  register_library("classloader");

  register_native("cl_registerClassLoader", "native_registerClassLoader");
  register_native("cl_loadClasses", "native_loadClasses");
}

//native cl_registerClassLoader(const callback[], const extension[], ...);
public native_registerClassLoader(plugin, numParams) {
#if defined COMPILE_FOR_DEBUG
  if (!numParamsGreaterEqual(2, numParams)) {
    return;
  }
#endif
  
  new callback[32];
  get_string(1, callback, charsmax(callback));
  
  new const onLoadClass = CreateOneForward(plugin, callback, FP_STRING, FP_STRING);
  if (!onLoadClass) {
    ThrowIllegalArgumentException("Could not find callback function \"%s\"", callback);
    return;
  }
  
  if (!classLoaders) {
    classLoaders = TrieCreate();
#if defined COMPILE_FOR_DEBUG
    assert classLoaders;
    logd("Initialized classLoaders container as celltrie %d", classLoaders);
#endif
  }

#if defined COMPILE_FOR_DEBUG
  if (!classLoaderPlugins) {
    classLoaderPlugins = TrieCreate();
  }
#endif

  new extension[32], len;
  new Array: callbacks;
  for (new param = 2; param <= numParams; param++) {
    len = get_string(param, extension, charsmax(extension));
    extension[len] = EOS;
    if (isStringEmpty(extension)) {
      logw("Cannot associate empty extension with a class loader");
      continue;
    }

#if defined COMPILE_FOR_DEBUG
    new name[32];
    get_plugin(plugin, .filename = name, .len1 = charsmax(name));
    name[strlen(name) - 5] = EOS;
    logd("Associating extension \"%s\" with %s::%s", extension, name, callback);
#endif
    new bool: keyExists = TrieGetCell(classLoaders, extension, callbacks);
    if (!keyExists) {
      callbacks = ArrayCreate(.reserved = 1);
      TrieSetCell(classLoaders, extension, callbacks);
#if defined COMPILE_FOR_DEBUG
      assert callbacks;
      logd("Initialized callbacks container as celltrie %d", callbacks);
#endif
    }

    ArrayPushCell(callbacks, onLoadClass);
#if defined COMPILE_FOR_DEBUG
    new Array: plugins;
    keyExists = TrieGetCell(classLoaderPlugins, extension, plugins);
    if (!keyExists) {
      plugins = ArrayCreate(.reserved = 1);
      TrieSetCell(classLoaderPlugins, extension, plugins);
    }

    ArrayPushCell(plugins, plugin);
#endif
  }
}

//native cl_loadClasses(const path[], const bool: recursive = true);
public native_loadClasses(plugin, numParams) {
#if defined COMPILE_FOR_DEBUG
  if (!numParamsEqual(2, numParams)) {
    return;
  }
#endif

  if (!classLoaders) {
    logw("Cannot load classes, no class loaders have been registered!");
    return;
  }

  new path[PLATFORM_MAX_PATH], len;
  len = get_string(1, path, charsmax(path));
  if (file_exists(path)) {
    loadClass(path, len);
  } else {
    new const bool: recursive = get_param(2);
    loadClasses(path, recursive);
  }
}
