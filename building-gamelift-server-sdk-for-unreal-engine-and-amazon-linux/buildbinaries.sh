#!/bin/bash

echo "Building the Unreal GameLift Server SDK binaries for Amazon Linux 2023..."

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

# Setup Docker buildx for multi-architecture builds
setup_buildx() {
    echo "Setting up Docker buildx for multi-architecture builds..."
    
    # Check if Docker buildx is available
    if ! docker buildx version &>/dev/null; then
        echo "Error: Docker buildx not available. Please use Docker 19.03 or newer."
        exit 1
    fi
    
    # Set up QEMU for multi-architecture emulation
    echo "Installing QEMU emulation support..."
    docker run --privileged --rm tonistiigi/binfmt --install arm64
    
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

# Clean up Docker to free space
cleanup_docker() {
    echo "Cleaning Docker to free up space..."
    docker system prune -f
    echo "Docker cleanup complete."
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
echo "2) ARM64 only (Note: This uses emulation and may be slower)"
echo "3) Both architectures (default)"
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
        echo "NOTE: ARM64 builds on x86 hosts use emulation which may be slow and resource-intensive."
        build_arm64=true
        ;;
    "" | 3)
        echo "Building for both architectures"
        echo "NOTE: ARM64 builds on x86 hosts use emulation which may be slow and resource-intensive."
        build_amd64=true
        build_arm64=true
        ;;
    *)
        echo "Invalid choice. Building for both architectures (default)"
        echo "NOTE: ARM64 builds on x86 hosts use emulation which may be slow and resource-intensive."
        build_amd64=true
        build_arm64=true
        ;;
esac

# Create output directories
mkdir -p output

# Clean up Docker to free space before starting
cleanup_docker

# Setup Docker buildx for multi-architecture builds 
# (only needed if building for ARM64 or both architectures)
if [[ "$build_arm64" = true ]]; then
    setup_buildx
fi

# Build for AMD64 (x86_64)
if [[ "$build_amd64" = true ]]; then
    echo "Building for AMD64 (x86_64) architecture..."
    mkdir -p output/amd64
    docker buildx build --progress=plain --platform=linux/amd64 \
                        --build-arg TARGETARCH=amd64 \
                        --build-arg OPENSSL_VERSION=${openssl_version} \
                        --output=type=local,dest=./output/amd64 \
                        --target=server .
    
    build_status=$?
    if [ $build_status -eq 0 ] && [ "$(ls -A output/amd64 2>/dev/null)" ]; then
        echo "Creating AMD64 zip file..."
        (cd output/amd64 && zip -r ../../AL2023GameliftUE5sdk-amd64.zip ./* || echo "Warning: zip creation failed")
    else
        echo "Error: AMD64 build failed or output directory is empty (status: $build_status)"
        # Show directory contents for debugging
        ls -la output/amd64
    fi
    
    # Clean Docker between builds to free up space
    cleanup_docker
fi

# Build for ARM64
if [[ "$build_arm64" = true ]]; then
    echo "Building for ARM64 architecture (via emulation)..."
    mkdir -p output/arm64
    
    echo "Starting ARM64 build - this may take a while due to emulation..."
    docker buildx build --progress=plain --platform=linux/arm64 \
                        --build-arg TARGETARCH=arm64 \
                        --build-arg OPENSSL_VERSION=${openssl_version} \
                        --output=type=local,dest=./output/arm64 \
                        --target=server .
    
    build_status=$?
    if [ $build_status -eq 0 ] && [ "$(ls -A output/arm64 2>/dev/null)" ]; then
        echo "Creating ARM64 zip file..."
        (cd output/arm64 && zip -r ../../AL2023GameliftUE5sdk-arm64.zip ./* || echo "Warning: zip creation failed")
    else
        echo "Error: ARM64 build failed or output directory is empty (status: $build_status)"
        # Show directory contents for debugging
        ls -la output/arm64
    fi
fi

# Create a combined zip file with both architectures if both were built
if [[ "$build_amd64" = true && "$build_arm64" = true ]] && \
   [ -f "AL2023GameliftUE5sdk-amd64.zip" ] && [ -f "AL2023GameliftUE5sdk-arm64.zip" ]; then
    echo "Creating multi-architecture package..."
    rm -rf combined
    mkdir -p combined/amd64
    mkdir -p combined/arm64
    
    # Extract the individual zip files to the combined directory
    unzip -o AL2023GameliftUE5sdk-amd64.zip -d combined/amd64 || echo "Warning: Error extracting AMD64 zip"
    unzip -o AL2023GameliftUE5sdk-arm64.zip -d combined/arm64 || echo "Warning: Error extracting ARM64 zip"
    
    # Create combined zip
    (cd combined && zip -r ../AL2023GameliftUE5sdk-multiarch.zip ./* || echo "Warning: Error creating multi-arch zip")
fi

echo "Build process completed."
echo ""
echo "The following files are available for download:"
if [[ "$build_amd64" = true ]] && [ -f "AL2023GameliftUE5sdk-amd64.zip" ]; then
    echo "- AMD64 (x86_64) binaries: AL2023GameliftUE5sdk-amd64.zip"
fi
if [[ "$build_arm64" = true ]] && [ -f "AL2023GameliftUE5sdk-arm64.zip" ]; then
    echo "- ARM64 binaries: AL2023GameliftUE5sdk-arm64.zip"
fi
if [[ "$build_amd64" = true && "$build_arm64" = true ]] && [ -f "AL2023GameliftUE5sdk-multiarch.zip" ]; then
    echo "- Multi-architecture package: AL2023GameliftUE5sdk-multiarch.zip"
fi

echo ""
echo "Select Actions -> Download File and type the full path to download the binaries."
echo "For example: /home/cloudshell-user/amazon-gamelift-toolkit/building-gamelift-server-sdk-for-unreal-engine-and-amazon-linux/AL2023GameliftUE5sdk-multiarch.zip"
