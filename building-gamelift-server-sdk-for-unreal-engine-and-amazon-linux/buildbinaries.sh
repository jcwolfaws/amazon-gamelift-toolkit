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

# Prompt for Unreal Engine version
echo ""
echo "Select your Unreal Engine version:"
echo "1) UE 5.0"
echo "2) UE 5.1"
echo "3) UE 5.2"
echo "4) UE 5.3"
echo "5) UE 5.4"
echo "6) UE 5.5"
echo "7) Other (specify custom OpenSSL version)"
read -p "Enter your choice [1-7] or press Enter for default (UE 5.2): " ue_choice

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
    echo "Using OpenSSL version ${openssl_version} for Unreal Engine ${ue_version}"
fi

# Prompt for architecture selection
echo ""
echo "Select which architecture(s) to build for:"
echo "1) x86_64 (AMD64) only"
echo "2) ARM64 only"
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
        build_arm64=true
        ;;
    "" | 3)
        echo "Building for both architectures"
        build_amd64=true
        build_arm64=true
        ;;
    *)
        echo "Invalid choice. Building for both architectures (default)"
        build_amd64=true
        build_arm64=true
        ;;
esac

# Create output directories
mkdir -p output

# Build for AMD64 (x86_64)
if [[ "$build_amd64" = true ]]; then
    echo "Building for AMD64 (x86_64) architecture..."
    mkdir -p output/amd64
    docker buildx build --platform=linux/amd64 --build-arg TARGETARCH=amd64 \
                        --build-arg OPENSSL_VERSION=${openssl_version} \
                        --output=./output/amd64 --target=server .
    
    echo "Creating AMD64 zip file..."
    cd output/amd64
    zip -r ../../AL2023GameliftUE5sdk-amd64.zip ./*
    cd ../..
fi

# Build for ARM64
if [[ "$build_arm64" = true ]]; then
    echo "Building for ARM64 architecture..."
    mkdir -p output/arm64
    docker buildx build --platform=linux/arm64 --build-arg TARGETARCH=arm64 \
                        --build-arg OPENSSL_VERSION=${openssl_version} \
                        --output=./output/arm64 --target=server .
    
    echo "Creating ARM64 zip file..."
    cd output/arm64
    zip -r ../../AL2023GameliftUE5sdk-arm64.zip ./*
    cd ../..
fi

# Create a combined zip file with both architectures if both were built
if [[ "$build_amd64" = true && "$build_arm64" = true ]]; then
    echo "Creating multi-architecture package..."
    mkdir -p combined/amd64
    mkdir -p combined/arm64
    cp output/amd64/lib* combined/amd64/
    cp output/arm64/lib* combined/arm64/
    cd combined
    zip -r ../AL2023GameliftUE5sdk-multiarch.zip ./*
    cd ..
fi

echo "Build complete! The following files are available for download:"
if [[ "$build_amd64" = true ]]; then
    echo "- AMD64 (x86_64) binaries: AL2023GameliftUE5sdk-amd64.zip"
fi
if [[ "$build_arm64" = true ]]; then
    echo "- ARM64 binaries: AL2023GameliftUE5sdk-arm64.zip"
fi
if [[ "$build_amd64" = true && "$build_arm64" = true ]]; then
    echo "- Multi-architecture package: AL2023GameliftUE5sdk-multiarch.zip"
fi

echo ""
echo "Select Actions -> Download File and type the full path to download the binaries."
echo "For example: /home/cloudshell-user/amazon-gamelift-toolkit/building-gamelift-server-sdk-for-unreal-engine-and-amazon-linux/AL2023GameliftUE5sdk-multiarch.zip"
