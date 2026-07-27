#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include "llama.h"
#include "llama_inference_engine.h"

#include <mutex>
#include <string>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
// NOMINMAX is already supplied by godot-cpp's build flags.
#include <windows.h>
#include <filesystem>
#endif

using namespace godot;

// ggml loads its backend plugins with a bare LoadLibraryW(absolute path) and no
// LOAD_WITH_ALTERED_SEARCH_PATH (ggml-backend-dl.cpp). Windows therefore resolves
// ggml-cuda.dll's *own* imports - cudart64_*, cublas64_*, cublasLt64_* - against
// the application directory, which for us is Godot's install folder, not this
// addon. The load fails, and it fails SILENTLY: ggml's dl_error() returns "" and
// the discovery pass is run with silent=true, so the CUDA backend simply never
// registers and every turn quietly runs on CPU. llama-server.exe never hits this
// because its application directory IS the folder holding every DLL.
//
// Pre-loading each third-party runtime DLL by absolute path fixes it: once a
// module is in the process, Windows satisfies imports naming it from the loaded
// module instead of searching the disk again. Absent files are not an error - a
// CPU-only install legitimately has no CUDA runtime beside it.
static void preload_runtime_dependencies(const std::string &p_bin_dir) {
#ifdef _WIN32
	std::error_code ec;
	std::filesystem::path dir(p_bin_dir);
	std::filesystem::directory_iterator it(dir, ec);
	if (ec) {
		return;
	}
	for (const auto &entry : it) {
		if (!entry.is_regular_file(ec) || ec) {
			continue;
		}
		const std::filesystem::path &path = entry.path();
		if (path.extension() != ".dll") {
			continue;
		}
		// ggml-* are the backend plugins ggml discovers and scores for itself;
		// outpost_llama is this module, already loaded.
		const std::string stem = path.stem().string();
		if (stem.rfind("ggml", 0) == 0 || stem.rfind("outpost_llama", 0) == 0) {
			continue;
		}
		LoadLibraryExW(path.wstring().c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
	}
#endif
}

// Resolved on the main thread at init (ProjectSettings is a main-thread service),
// consumed later by the worker thread that actually loads the backends.
//
// Deliberately a std::string, not a godot::String: a godot::String at namespace
// scope is constructed during static initialization, before the GDExtension
// interface binds its function pointers, and the call into the unbound API aborts
// the DLL's init routine. Windows reports only "Error 1114: a dynamic link
// library (DLL) initialization routine failed" and the whole extension fails to
// load. Never give this module a namespace-scope Godot type.
static std::string _backend_search_path;
static std::once_flag _backends_loaded_once;

void outpost_ensure_ggml_backends_loaded() {
	std::call_once(_backends_loaded_once, []() {
		// ggml's CPU/CUDA backends are separate plugin DLLs (ggml-cpu-*.dll,
		// ggml-cuda.dll), not baked into llama.dll. Auto-discovery searches the
		// executable's directory and the working directory - neither of which is
		// this addon's bin/ folder - so point it there explicitly.
		preload_runtime_dependencies(_backend_search_path);
		ggml_backend_load_all_from_path(_backend_search_path.c_str());

		String devices;
		for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
			if (i > 0) {
				devices += ", ";
			}
			devices += ggml_backend_dev_name(ggml_backend_dev_get(i));
		}
		UtilityFunctions::print("outpost_llama: ggml devices available: ", devices);
	});
}

void initialize_outpost_llama_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	llama_backend_init();
	_backend_search_path = ProjectSettings::get_singleton()
								   ->globalize_path("res://addons/outpost_llama/bin")
								   .utf8()
								   .get_data();
	GDREGISTER_CLASS(LlamaInferenceEngine);
}

void uninitialize_outpost_llama_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	llama_backend_free();
}

extern "C" {
GDExtensionBool GDE_EXPORT outpost_llama_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_outpost_llama_module);
	init_obj.register_terminator(uninitialize_outpost_llama_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
