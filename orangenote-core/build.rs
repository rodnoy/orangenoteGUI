//! Build script for orangenote-core
//!
//! This script handles compilation of whisper.cpp when the `whisper` feature is enabled.
//! Priority: 1) System installation (Homebrew), 2) Git submodule

use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    // Only link whisper if the feature is enabled
    #[cfg(feature = "whisper")]
    {
        link_whisper();
    }

    println!("cargo:rerun-if-changed=build.rs");
}

#[cfg(feature = "whisper")]
fn link_whisper() {
    // Priority 1: Try to find system-installed whisper (Homebrew, etc.)
    if try_link_system_whisper() {
        return;
    }

    // Priority 2: Try to build from git submodule if it exists
    let whisper_dir = PathBuf::from("../vendor/whisper.cpp");
    if whisper_dir.exists() {
        println!("cargo:warning=Building whisper.cpp from git submodule...");
        if build_from_submodule(&whisper_dir) {
            return;
        }
    }

    // If we reach here, we couldn't find whisper
    println!(
        "cargo:warning=whisper.cpp not found!\n\
         To fix this, choose one of these options:\n\n\
         Option 1 (Recommended for macOS): Install via Homebrew\n\
           brew install whisper-cpp\n\n\
         Option 2: Clone as git submodule\n\
           git submodule add https://github.com/ggerganov/whisper.cpp vendor/whisper.cpp\n\
           git submodule update --init --recursive\n\n\
         After that, rebuild with:\n\
           cargo clean\n\
           cargo build --features whisper --release"
    );
}

#[cfg(feature = "whisper")]
fn try_link_system_whisper() -> bool {
    // Try macOS Homebrew paths first
    #[cfg(target_os = "macos")]
    {
        let homebrew_paths = vec![
            (
                "/opt/homebrew/opt/whisper-cpp/lib",
                "/opt/homebrew/opt/whisper-cpp/include",
            ), // Apple Silicon
            ("/opt/homebrew/lib", "/opt/homebrew/include"), // Apple Silicon fallback
            (
                "/usr/local/opt/whisper-cpp/lib",
                "/usr/local/opt/whisper-cpp/include",
            ), // Intel Homebrew
            ("/usr/local/lib", "/usr/local/include"),       // Intel fallback
        ];

        for (lib_path, inc_path) in homebrew_paths {
            let libwhisper = PathBuf::from(lib_path).join("libwhisper.a");
            let whisper_h = PathBuf::from(inc_path).join("whisper.h");

            if libwhisper.exists() && whisper_h.exists() {
                println!(
                    "cargo:warning=Found system whisper.cpp at: {}",
                    libwhisper.display()
                );
                println!("cargo:rustc-link-search=native={}", lib_path);
                println!("cargo:rustc-link-lib=static=whisper");

                // Add any system frameworks needed
                println!("cargo:rustc-link-search=native=/usr/local/lib");
                println!("cargo:rustc-link-search=native=/opt/homebrew/lib");

                return true;
            }
        }
    }

    // Try Linux paths
    #[cfg(target_os = "linux")]
    {
        let linux_paths = vec![
            "/usr/lib",
            "/usr/local/lib",
            "/usr/lib/x86_64-linux-gnu",
            "/usr/lib/aarch64-linux-gnu",
        ];

        for lib_path in linux_paths {
            let libwhisper = PathBuf::from(lib_path).join("libwhisper.a");
            if libwhisper.exists() {
                println!(
                    "cargo:warning=Found system whisper.cpp at: {}",
                    libwhisper.display()
                );
                println!("cargo:rustc-link-search=native={}", lib_path);
                println!("cargo:rustc-link-lib=static=whisper");
                return true;
            }
        }
    }

    false
}

#[cfg(feature = "whisper")]
fn find_cmake() -> Option<String> {
    // Try common cmake locations
    let cmake_paths = vec![
        "/opt/homebrew/bin/cmake", // Homebrew Apple Silicon
        "/usr/local/bin/cmake",    // Homebrew Intel
        "/usr/bin/cmake",          // System
        "/opt/local/bin/cmake",    // MacPorts
    ];

    for path in cmake_paths {
        if PathBuf::from(path).exists() {
            return Some(path.to_string());
        }
    }

    // Try to find cmake in PATH
    if Command::new("which")
        .arg("cmake")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
    {
        return Some("cmake".to_string());
    }

    None
}

#[cfg(feature = "whisper")]
fn build_from_submodule(whisper_dir: &PathBuf) -> bool {
    // Check if CMakeLists.txt exists (confirming submodule is initialized)
    let cmake_file = whisper_dir.join("CMakeLists.txt");
    if !cmake_file.exists() {
        println!(
            "cargo:warning=Git submodule not initialized. Run:\n\
             git submodule update --init --recursive"
        );
        return false;
    }

    let out_dir = env::var("OUT_DIR").expect("OUT_DIR not set");
    let build_dir = PathBuf::from(&out_dir).join("whisper_build");

    // Create build directory
    std::fs::create_dir_all(&build_dir).expect("Failed to create build directory");

    // Get absolute path to whisper source
    let abs_whisper_dir =
        std::fs::canonicalize(whisper_dir).expect("Failed to get absolute path to whisper.cpp");

    // Try to find cmake - check common locations
    let cmake_cmd = find_cmake().unwrap_or_else(|| "cmake".to_string());
    println!("cargo:warning=Using cmake: {}", cmake_cmd);
    println!("cargo:warning=Build directory: {}", build_dir.display());
    println!(
        "cargo:warning=Source directory: {}",
        abs_whisper_dir.display()
    );

    // Run cmake configure
    println!("cargo:warning=Running cmake configure...");
    
    // Detect cross-compilation
    let target = env::var("TARGET").unwrap_or_default();
    let host = env::var("HOST").unwrap_or_default();
    let is_cross_compiling = target != host;
    
    println!("cargo:warning=Target: {}", target);
    println!("cargo:warning=Host: {}", host);
    println!("cargo:warning=Cross-compiling: {}", is_cross_compiling);
    
    let mut cmake_configure_cmd = Command::new(&cmake_cmd);
    cmake_configure_cmd
        .current_dir(&build_dir)
        .arg("-DCMAKE_BUILD_TYPE=Release")
        .arg("-DBUILD_SHARED_LIBS=OFF")
        .arg("-DWHISPER_CPP_ONLY=ON")
        .arg("-DGGML_OPENMP=OFF")
        .arg("-DWHISPER_NO_OPENMP=ON");

    // Handle cross-compilation for macOS
    #[cfg(target_os = "macos")]
    {
        if is_cross_compiling {
            // Remove environment variables that may carry host-specific CPU flags
            // (e.g. CFLAGS="-mcpu=apple-m1") and leak them into the CMake build.
            cmake_configure_cmd.env_remove("CFLAGS");
            cmake_configure_cmd.env_remove("CXXFLAGS");
            cmake_configure_cmd.env_remove("CPPFLAGS");

            // Cross-compiling on macOS
            if target.contains("x86_64") && host.contains("aarch64") {
                // Building x86_64 on Apple Silicon
                println!("cargo:warning=Configuring for x86_64 cross-compilation on Apple Silicon");
                cmake_configure_cmd.arg("-DCMAKE_OSX_ARCHITECTURES=x86_64");
                cmake_configure_cmd.arg("-DCMAKE_SYSTEM_PROCESSOR=x86_64");
                cmake_configure_cmd.arg("-DCMAKE_SYSTEM_NAME=Darwin");
                // Explicitly set C/C++ flags for x86_64 to override any host-specific flags
                cmake_configure_cmd.arg("-DCMAKE_C_FLAGS=-arch x86_64");
                cmake_configure_cmd.arg("-DCMAKE_CXX_FLAGS=-arch x86_64");
                // Explicitly disable ARM-specific optimizations
                cmake_configure_cmd.arg("-DGGML_METAL=OFF");
                // CRITICAL: Disable GGML_NATIVE to prevent -mcpu=apple-m1 from being added
                // When GGML_NATIVE=ON, ggml runs the compiler with -mcpu=native which returns
                // -mcpu=apple-m1 on Apple Silicon host, breaking x86_64 cross-compilation
                cmake_configure_cmd.arg("-DGGML_NATIVE=OFF");
            } else if target.contains("aarch64") && host.contains("x86_64") {
                // Building ARM on Intel (less common but possible)
                println!("cargo:warning=Configuring for ARM64 cross-compilation on Intel");
                cmake_configure_cmd.arg("-DCMAKE_OSX_ARCHITECTURES=arm64");
                cmake_configure_cmd.arg("-DCMAKE_SYSTEM_PROCESSOR=arm64");
                cmake_configure_cmd.arg("-DCMAKE_SYSTEM_NAME=Darwin");
                cmake_configure_cmd.arg("-DCMAKE_C_FLAGS=-arch arm64");
                cmake_configure_cmd.arg("-DCMAKE_CXX_FLAGS=-arch arm64");
                // Disable GGML_NATIVE for cross-compilation
                cmake_configure_cmd.arg("-DGGML_NATIVE=OFF");
            }
        } else {
            // Native compilation - let CMake detect architecture
            if target.contains("x86_64") {
                cmake_configure_cmd.arg("-DCMAKE_OSX_ARCHITECTURES=x86_64");
            } else if target.contains("aarch64") {
                cmake_configure_cmd.arg("-DCMAKE_OSX_ARCHITECTURES=arm64");
            }
        }
    }

    cmake_configure_cmd.arg(&abs_whisper_dir);

    let cmake_output = cmake_configure_cmd.output();

    match cmake_output {
        Ok(output) if output.status.success() => {
            println!("cargo:warning=CMake configuration succeeded");
        }
        Ok(output) => {
            println!("cargo:warning=CMake configuration failed!");
            println!(
                "cargo:warning=stdout: {}",
                String::from_utf8_lossy(&output.stdout)
            );
            println!(
                "cargo:warning=stderr: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            return false;
        }
        Err(e) => {
            println!("cargo:warning=Failed to run cmake: {}", e);
            return false;
        }
    }

    // Run cmake build
    println!("cargo:warning=Running cmake build...");
    let mut cmake_build_cmd = Command::new(&cmake_cmd);
    cmake_build_cmd
        .arg("--build")
        .arg(&build_dir)
        .arg("--config")
        .arg("Release");

    // Strip host-specific flags from the build environment during cross-compilation
    if is_cross_compiling {
        cmake_build_cmd.env_remove("CFLAGS");
        cmake_build_cmd.env_remove("CXXFLAGS");
        cmake_build_cmd.env_remove("CPPFLAGS");
    }

    let cmake_build_output = cmake_build_cmd.output();

    match cmake_build_output {
        Ok(output) if output.status.success() => {
            println!("cargo:warning=CMake build succeeded");
        }
        Ok(output) => {
            println!("cargo:warning=CMake build failed!");
            println!(
                "cargo:warning=build stdout: {}",
                String::from_utf8_lossy(&output.stdout)
            );
            println!(
                "cargo:warning=build stderr: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            return false;
        }
        Err(e) => {
            println!("cargo:warning=Failed to run cmake build: {}", e);
            return false;
        }
    }

    // Check if library was built - try multiple possible locations
    let possible_lib_paths = vec![
        build_dir.join("src").join("libwhisper.a"),
        build_dir.join("bin").join("libwhisper.a"),
        build_dir.join("lib").join("libwhisper.a"),
        build_dir.join("libwhisper.a"),
    ];

    let mut found_lib_path: Option<PathBuf> = None;
    for path in &possible_lib_paths {
        if path.exists() {
            found_lib_path = Some(path.clone());
            break;
        }
    }

    let lib_path = match found_lib_path {
        Some(path) => path,
        None => {
            println!("cargo:warning=Whisper library not found in any of:");
            for path in &possible_lib_paths {
                println!("cargo:warning=  - {}", path.display());
            }
            return false;
        }
    };

    let lib_dir = lib_path.parent().expect("Library path has no parent");
    println!(
        "cargo:warning=Found whisper library at: {}",
        lib_path.display()
    );
    println!("cargo:warning=Linking with built whisper.cpp");
    println!("cargo:rustc-link-search=native={}", lib_dir.display());

    // Also add ggml library paths
    let ggml_dir = build_dir.join("ggml").join("src");
    let ggml_metal_dir = ggml_dir.join("ggml-metal");
    let ggml_blas_dir = ggml_dir.join("ggml-blas");

    if ggml_dir.exists() {
        println!("cargo:rustc-link-search=native={}", ggml_dir.display());
    }
    if ggml_metal_dir.exists() {
        println!(
            "cargo:rustc-link-search=native={}",
            ggml_metal_dir.display()
        );
    }
    if ggml_blas_dir.exists() {
        println!("cargo:rustc-link-search=native={}", ggml_blas_dir.display());
    }

    // Link whisper and ggml libraries in correct order (dependencies last)
    println!("cargo:rustc-link-lib=static=whisper");
    println!("cargo:rustc-link-lib=static=ggml");
    println!("cargo:rustc-link-lib=static=ggml-base");
    println!("cargo:rustc-link-lib=static=ggml-cpu");

    // Link optional ggml backends if they exist
    if ggml_metal_dir.join("libggml-metal.a").exists() {
        println!("cargo:rustc-link-lib=static=ggml-metal");
    }
    if ggml_blas_dir.join("libggml-blas.a").exists() {
        println!("cargo:rustc-link-lib=static=ggml-blas");
    }

    // Link C++ standard library
    #[cfg(target_os = "macos")]
    {
        println!("cargo:rustc-link-lib=c++");
        // Link Apple frameworks required by whisper.cpp
        println!("cargo:rustc-link-lib=framework=Accelerate");
        println!("cargo:rustc-link-lib=framework=Foundation");
        println!("cargo:rustc-link-lib=framework=Metal");
        println!("cargo:rustc-link-lib=framework=MetalKit");
    }

    #[cfg(target_os = "linux")]
    {
        println!("cargo:rustc-link-lib=stdc++");
        println!("cargo:rustc-link-lib=m");
        println!("cargo:rustc-link-lib=pthread");
    }

    true
}
