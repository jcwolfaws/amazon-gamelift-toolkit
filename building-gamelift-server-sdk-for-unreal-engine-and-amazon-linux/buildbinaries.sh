#!/bin/bash

echo "Building the Unreal GameLift Server SDK binaries for Amazon Linux 2023..."

# Start timing total build process
build_start_time=$(date +%s)

# Initialize build status trackers
amd64_build_status=255  # Not attempted
arm64_build_status=255  # Not attempted
enable_caching=false    # Default: no caching to avoid using excess disk space

# Function to format time duration
format_duration() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    
    if [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${remaining_seconds}s"
    else
        echo "${seconds}s"
    fi
}

# Map UE versions to OpenSSL versions
get_openssl_version() {
    local ue_version=$1
    
    case "$ue_version" in
        "5.0")
            echo "1.1.1l"  # UE 5.0 uses OpenSSL 1.1.1l
            ;;
        "5.1")
            echo "1.1.1n"  # UE 5.1 uses OpenSSL 1.1.1n
            ;;
        "5.2")
            echo "1.1.1n"  # UE 5.2 uses OpenSSL 1.1.1n
            ;;
        "5.3")
            echo "1.1.1t"  # UE 5.3 uses OpenSSL 1.1.1t
            ;;
        "5.4")
            echo "1.1.1t"  # UE 5.4 uses OpenSSL 1.1.1t
            ;;
        "5.5")
            echo "1.1.1t"  # UE 5.5 uses OpenSSL 1.1.1t
            ;;
        *)
            echo "1.1.1t"  # Default for unknown versions (using the latest)
            ;;
    esac
}

# Detect host system architecture
detect_host_architecture() {
    # Get system architecture
    local arch=$(uname -m)
    
    if [[ "$arch" == "x86_64" ]]; then
        echo "x86_64"
    elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
        echo "arm64"
    else
        echo "Unknown architecture: $arch"
        echo "This script is designed for x86_64 or arm64 hosts. Assuming x86_64..."
        echo "x86_64"
    fi
}

# Get host architecture
HOST_ARCH=$(detect_host_architecture)
echo "Detected host architecture: $HOST_ARCH"

# Setup Docker buildx for multi-architecture builds
setup_buildx() {
    echo "Setting up Docker buildx for multi-architecture builds..."
    
    # Check if Docker buildx is available
    if ! docker buildx version &>/dev/null; then
        echo "Error: Docker buildx not available. Please use Docker 19.03 or newer."
        exit 1
    fi
    
    # Set up QEMU for cross-architecture emulation
    # Only install emulation for architectures different from the host
    if [[ "$HOST_ARCH" == "x86_64" && "$build_arm64" == "true" ]]; then
        echo "Installing QEMU emulation support for ARM64..."
        docker run --privileged --rm tonistiigi/binfmt --install arm64
    elif [[ "$HOST_ARCH" == "arm64" && "$build_amd64" == "true" ]]; then
        echo "Installing QEMU emulation support for AMD64..."
        docker run --privileged --rm tonistiigi/binfmt --install amd64
    fi
    
    # Create a new builder instance if it doesn't exist
    if ! docker buildx inspect mybuilder &>/dev/null; then
        docker buildx create --name mybuilder --use
    else
        docker buildx use mybuilder
    fi
    
    # Bootstrap the builder
    docker buildx inspect --bootstrap
    
    echo "Docker buildx setup complete."
}

# Prompt for Unreal Engine version
echo ""
echo "Select your Unreal Engine version to determine the correct OpenSSL version:"
echo "Each UE version requires a specific OpenSSL version for compatibility"
echo "-----------------------------------------------------------------------------"
echo "1) UE 5.0 (uses OpenSSL 1.1.1l)"
echo "2) UE 5.1 (uses OpenSSL 1.1.1n)"
echo "3) UE 5.2 (uses OpenSSL 1.1.1n)"
echo "4) UE 5.3 (uses OpenSSL 1.1.1t)"
echo "5) UE 5.4 (uses OpenSSL 1.1.1t)"
echo "6) UE 5.5 (uses OpenSSL 1.1.1t)"
echo "7) Other (specify custom OpenSSL version)"
echo "-----------------------------------------------------------------------------"
read -p "Enter your choice [1-7] or press Enter for default (UE 5.2 with OpenSSL 1.1.1n): " ue_choice

# Set UE version based on user choice
case "$ue_choice" in
    1)
        ue_version="5.0"
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
    2)
        ue_version="5.1"
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
    ""|3)
        ue_version="5.2"  # Default
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
    4)
        ue_version="5.3"
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
    5)
        ue_version="5.4"
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
    6)
        ue_version="5.5"
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
    7)
        echo "You've selected to use a custom OpenSSL version."
        echo "NOTE: This should match the OpenSSL version used by your Unreal Engine installation."
        echo "      Check Engine/Source/ThirdParty/OpenSSL in your UE source directory to confirm."
        read -p "Enter the OpenSSL version (e.g., 1.1.1k, 1.1.1q): " custom_openssl
        if [[ -z "$custom_openssl" ]]; then
            echo "No version provided. Using default (1.1.1t)"
            openssl_version="1.1.1t"
        else
            openssl_version="$custom_openssl"
            ue_version="custom"
        fi
        ;;
    *)
        echo "Invalid choice. Using default (UE 5.2)"
        ue_version="5.2"
        openssl_version=$(get_openssl_version "$ue_version")
        ;;
esac

if [[ "$ue_version" == "custom" ]]; then
    echo "Using custom OpenSSL version ${openssl_version}"
else
    echo "Selected Unreal Engine ${ue_version} - Will build with OpenSSL ${openssl_version}"
fi

# Prompt for architecture selection
echo ""
echo "Select which architecture(s) to build for:"
echo "1) x86_64 (AMD64) only"
echo "2) ARM64 only"
echo "3) Both architectures (default)"

# Display recommendations based on host architecture
if [[ "$HOST_ARCH" == "arm64" ]]; then
    echo ""
    echo "NOTE: You are running on an ARM64 host. Building for ARM64 will be native (fast),"
    echo "      but building for x86_64 will require emulation (slower)."
    echo "      For best performance, consider building only for ARM64 on this host."
elif [[ "$HOST_ARCH" == "x86_64" ]]; then
    echo ""
    echo "NOTE: You are running on an x86_64 host. Building for x86_64 will be native (fast),"
    echo "      but building for ARM64 will require emulation (slower)."
fi

read -p "Enter your choice [1-3] or press Enter for default: " arch_choice

# Set flags based on user choice
build_amd64=false
build_arm64=false
case "$arch_choice" in
    1)
        echo "Building for x86_64 (AMD64) only"
        build_amd64=true
        ;;
    2)
        echo "Building for ARM64 only"
        if [[ "$HOST_ARCH" != "arm64" ]]; then
            echo "NOTE: ARM64 builds on x86_64 hosts use emulation which may be slow and resource-intensive."
        fi
        build_arm64=true
        ;;
    "" | 3)
        echo "Building for both architectures"
        if [[ "$HOST_ARCH" == "arm64" ]]; then
            echo "NOTE: x86_64 builds on ARM64 hosts use emulation which may be slow and resource-intensive."
        elif [[ "$HOST_ARCH" == "x86_64" ]]; then
            echo "NOTE: ARM64 builds on x86_64 hosts use emulation which may be slow and resource-intensive."
        fi
        build_amd64=true
        build_arm64=true
        ;;
    *)
        echo "Invalid choice. Building for both architectures (default)"
        if [[ "$HOST_ARCH" == "arm64" ]]; then
            echo "NOTE: x86_64 builds on ARM64 hosts use emulation which may be slow and resource-intensive."
        elif [[ "$HOST_ARCH" == "x86_64" ]]; then
            echo "NOTE: ARM64 builds on x86_64 hosts use emulation which may be slow and resource-intensive."
        fi
        build_amd64=true
        build_arm64=true
        ;;
esac

# Ask about Docker caching
echo ""
echo "Enable Docker caching?"
echo "Caching can speed up subsequent builds but uses more disk space."
echo "1) No caching (default, recommended for one-time builds)"
echo "2) Enable caching (faster for repeated builds)"
read -p "Enter your choice [1-2] or press Enter for default: " cache_choice

case "$cache_choice" in
    2)
        echo "Docker caching enabled for faster repeated builds."
        enable_caching=true
        ;;
    * | "")
        echo "Docker caching disabled (default)."
        enable_caching=false
        ;;
esac

# Create output directories
mkdir -p output

# We don't create cache directories in /tmp anymore as they could interfere with other processes
# or be removed unexpectedly by the system

# Setup Docker buildx for multi-architecture builds 
# (only needed if building for cross-architecture)
need_buildx=false
if [[ "$HOST_ARCH" == "x86_64" && "$build_arm64" == "true" ]]; then
    need_buildx=true
elif [[ "$HOST_ARCH" == "arm64" && "$build_amd64" == "true" ]]; then
    need_buildx=true
fi

if [[ "$need_buildx" == "true" ]]; then
    setup_buildx
fi

# Build for AMD64 (x86_64)
if [[ "$build_amd64" = true ]]; then
    if [[ "$HOST_ARCH" == "x86_64" ]]; then
        echo "Building for AMD64 (x86_64) architecture (native build)..."
    else
        echo "Building for AMD64 (x86_64) architecture via emulation (this may take a while)..."
    fi
    
    mkdir -p output/amd64
    
    # Start timing
    amd64_build_start=$(date +%s)
    
    # For native builds, we can use regular docker build which is faster
    # For cross-architecture builds, we need to use buildx
    if [[ "$HOST_ARCH" == "x86_64" ]]; then
        if [[ "$enable_caching" == "true" ]]; then
            docker build --progress=auto \
                     --build-arg TARGETARCH=amd64 \
                     --build-arg OPENSSL_VERSION=${openssl_version} \
                     --output=type=local,dest=./output/amd64 \
                     --target=server .
        else
            docker build --progress=auto \
                     --build-arg TARGETARCH=amd64 \
                     --build-arg OPENSSL_VERSION=${openssl_version} \
                     --output=type=local,dest=./output/amd64 \
                     --no-cache \
                     --target=server .
        fi
    else
        # Use buildx for cross-platform builds
        if [[ "$enable_caching" == "true" ]]; then
            docker buildx build --progress=auto --platform=linux/amd64 \
                         --build-arg TARGETARCH=amd64 \
                         --build-arg OPENSSL_VERSION=${openssl_version} \
                         --output=type=local,dest=./output/amd64 \
                         --target=server .
        else
            docker buildx build --progress=auto --platform=linux/amd64 \
                         --build-arg TARGETARCH=amd64 \
                         --build-arg OPENSSL_VERSION=${openssl_version} \
                         --output=type=local,dest=./output/amd64 \
                         --no-cache \
                         --target=server .
        fi
    fi
    
    amd64_build_status=$?
    
    # Calculate build duration
    amd64_build_end=$(date +%s)
    amd64_build_duration=$((amd64_build_end - amd64_build_start))
    amd64_build_time=$(format_duration $amd64_build_duration)
    
    if [ $amd64_build_status -eq 0 ] && [ "$(ls -A output/amd64 2>/dev/null)" ]; then
        echo "Creating AMD64 zip file..."
        (cd output/amd64 && zip -q -r ../../AL2023GameliftUE5sdk-amd64.zip ./* > /dev/null 2>&1 || echo "Warning: zip creation failed")
        echo "✅ AMD64 build completed successfully (took $amd64_build_time)"
    else
        echo "❌ Error: AMD64 build failed or output directory is empty (status: $amd64_build_status, took $amd64_build_time)"
        # Show directory contents for debugging
        ls -la output/amd64
    fi
    
    # Don't clean Docker between builds to preserve cache and avoid
    # inadvertently affecting other Docker resources on the system
fi

# Build for ARM64
if [[ "$build_arm64" = true ]]; then
    if [[ "$HOST_ARCH" == "arm64" ]]; then
        echo "Building for ARM64 architecture (native build)..."
    else
        echo "Building for ARM64 architecture via emulation (this may take a while)..."
    fi
    
    mkdir -p output/arm64
    
    # Start timing
    arm64_build_start=$(date +%s)
    
    # For native builds, we can use regular docker build which is faster
    # For cross-architecture builds, we need to use buildx
    if [[ "$HOST_ARCH" == "arm64" ]]; then
        if [[ "$enable_caching" == "true" ]]; then
            docker build --progress=auto \
                     --build-arg TARGETARCH=arm64 \
                     --build-arg OPENSSL_VERSION=${openssl_version} \
                     --output=type=local,dest=./output/arm64 \
                     --target=server .
        else
            docker build --progress=auto \
                     --build-arg TARGETARCH=arm64 \
                     --build-arg OPENSSL_VERSION=${openssl_version} \
                     --output=type=local,dest=./output/arm64 \
                     --no-cache \
                     --target=server .
        fi
    else
        # Use buildx for cross-platform builds
        if [[ "$enable_caching" == "true" ]]; then
            docker buildx build --progress=auto --platform=linux/arm64 \
                         --build-arg TARGETARCH=arm64 \
                         --build-arg OPENSSL_VERSION=${openssl_version} \
                         --output=type=local,dest=./output/arm64 \
                         --target=server .
        else
            docker buildx build --progress=auto --platform=linux/arm64 \
                         --build-arg TARGETARCH=arm64 \
                         --build-arg OPENSSL_VERSION=${openssl_version} \
                         --output=type=local,dest=./output/arm64 \
                         --no-cache \
                         --target=server .
        fi
    fi
    
    arm64_build_status=$?
    
    # Calculate build duration
    arm64_build_end=$(date +%s)
    arm64_build_duration=$((arm64_build_end - arm64_build_start))
    arm64_build_time=$(format_duration $arm64_build_duration)
    
    if [ $arm64_build_status -eq 0 ] && [ "$(ls -A output/arm64 2>/dev/null)" ]; then
        echo "Creating ARM64 zip file..."
        (cd output/arm64 && zip -q -r ../../AL2023GameliftUE5sdk-arm64.zip ./* > /dev/null 2>&1 || echo "Warning: zip creation failed")
        echo "✅ ARM64 build completed successfully (took $arm64_build_time)"
    else
        echo "❌ Error: ARM64 build failed or output directory is empty (status: $arm64_build_status, took $arm64_build_time)"
        # Show directory contents for debugging
        ls -la output/arm64
    fi
    
    # We're not cleaning up after builds to avoid affecting other Docker resources
    # Users can manually clean up if needed after the build completes
fi

# Create a combined zip file with both architectures if both were successfully built
if [ -f "AL2023GameliftUE5sdk-amd64.zip" ] && [ -f "AL2023GameliftUE5sdk-arm64.zip" ]; then
    echo "Creating multi-architecture package..."
    rm -rf combined
    mkdir -p combined/amd64
    mkdir -p combined/arm64
    
    # Extract the individual zip files to the combined directory
    unzip -q -o AL2023GameliftUE5sdk-amd64.zip -d combined/amd64 > /dev/null || echo "Warning: Error extracting AMD64 zip"
    unzip -q -o AL2023GameliftUE5sdk-arm64.zip -d combined/arm64 > /dev/null || echo "Warning: Error extracting ARM64 zip"
    
    # Create combined zip
    (cd combined && zip -q -r ../AL2023GameliftUE5sdk-multiarch.zip ./* > /dev/null 2>&1 || echo "Warning: Error creating multi-arch zip")
fi

# Clean up temporary directories after successful builds
# Clean up combined directory if it exists and the multiarch zip was created
if [ -d "combined" ] && [ -f "AL2023GameliftUE5sdk-multiarch.zip" ]; then
    echo "Cleaning up temporary combined directory..."
    rm -rf combined
fi

# Clean up output directory if at least one build succeeded
if [ -f "AL2023GameliftUE5sdk-amd64.zip" ] || [ -f "AL2023GameliftUE5sdk-arm64.zip" ]; then
    echo "Cleaning up temporary output directories..."
    rm -rf output
fi

echo ""
echo "========================================================================"
echo "                          BUILD RESULTS"
echo "========================================================================"

# Report status of each build
if [[ "$build_amd64" = true ]]; then
    if [ $amd64_build_status -eq 0 ] && [ -f "AL2023GameliftUE5sdk-amd64.zip" ]; then
        echo "✅ AMD64 (x86_64) build: SUCCESS (took $amd64_build_time)"
    else
        echo "❌ AMD64 (x86_64) build: FAILED (status: $amd64_build_status, took $amd64_build_time)"
    fi
fi

if [[ "$build_arm64" = true ]]; then
    if [ $arm64_build_status -eq 0 ] && [ -f "AL2023GameliftUE5sdk-arm64.zip" ]; then
        echo "✅ ARM64 build: SUCCESS (took $arm64_build_time)"
    else
        echo "❌ ARM64 build: FAILED (status: $arm64_build_status, took $arm64_build_time)"
    fi
fi

# Multi-arch package status
if [[ "$build_amd64" = true && "$build_arm64" = true ]]; then
    if [ -f "AL2023GameliftUE5sdk-multiarch.zip" ]; then
        echo "✅ Multi-architecture package: SUCCESS"
    else
        echo "❌ Multi-architecture package: NOT CREATED (requires both architectures to succeed)"
    fi
fi

echo ""
echo "The following files are available for download:"
if [ -f "AL2023GameliftUE5sdk-amd64.zip" ]; then
    echo "- AMD64 (x86_64) binaries: AL2023GameliftUE5sdk-amd64.zip"
fi
if [ -f "AL2023GameliftUE5sdk-arm64.zip" ]; then
    echo "- ARM64 binaries: AL2023GameliftUE5sdk-arm64.zip"
fi
if [ -f "AL2023GameliftUE5sdk-multiarch.zip" ]; then
    echo "- Multi-architecture package: AL2023GameliftUE5sdk-multiarch.zip"
fi

echo ""
echo "If on CloudShell, select Actions -> Download File and type the full path to download the binaries."
echo "For example: /home/cloudshell-user/amazon-gamelift-toolkit/building-gamelift-server-sdk-for-unreal-engine-and-amazon-linux/AL2023GameliftUE5sdk-multiarch.zip"

echo ""
if [[ "$enable_caching" == "true" ]]; then
    echo "NOTE: Docker caching was enabled for this build. If you need to free up disk space"
    echo "      after the build is complete, you can run 'docker system prune' manually."
fi

# Calculate and display total build time
build_end_time=$(date +%s)
total_build_duration=$((build_end_time - build_start_time))
total_build_time=$(format_duration $total_build_duration)
echo ""
echo "Total build process time: $total_build_time"
