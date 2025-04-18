FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS build-server

# Set architecture as build arg with default to amd64
ARG TARGETARCH=amd64
ARG BUILDPLATFORM
# Set OpenSSL version as build arg with default to 1.1.1n (compatible with UE 5.1, 5.2)
ARG OPENSSL_VERSION=1.1.1n

# Install only the essential dependencies with minimal extras
RUN yum install -y -q --setopt=install_weak_deps=False \
    gcc-c++ cmake3 git wget openssl-devel tar perl sudo findutils \
    && yum clean all -q \
    && rm -rf /var/cache/yum

# Debug architecture information
RUN echo "BUILDPLATFORM: ${BUILDPLATFORM}" && \
    echo "TARGETARCH: ${TARGETARCH}" && \
    uname -a

# Format OpenSSL version string for download URL
RUN echo "Configuring OpenSSL version ${OPENSSL_VERSION}" && \
    OPENSSL_FORMAT_VERSION=$(echo "${OPENSSL_VERSION}" | tr '.' '_')

# Install correct OpenSSL version based on build arg
RUN wget -q https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz && \
    tar -xzf OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz && \
    cd openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/ && \
    # Configure with arch-specific optimization flags
    if [ "$(uname -m)" = "aarch64" ] || [ "$TARGETARCH" = "arm64" ]; then \
      echo "Detected ARM architecture - using ARM64 configuration" && \
      # ARM64-specific configuration - don't use arch flag in emulation
      ./config no-asm --libdir=/usr/local/lib64 --openssldir=/usr/local/ssl shared > /dev/null; \
    else \
      echo "Using AMD64 configuration" && \
      # AMD64-specific configuration
      ./config -m64 --libdir=/usr/local/lib64 --openssldir=/usr/local/ssl shared > /dev/null; \
    fi && \
    make -j$(nproc) > /dev/null && \
    make install > /dev/null && \
    cd .. && \
    rm -rf OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/

# Make sure OpenSSL is correctly installed and find the library files
RUN export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib64:/usr/lib && \
    openssl version && \
    echo "Locating OpenSSL libraries..." 

# Find and copy the OpenSSL library files to the binaries folder
RUN mkdir -p /binaries/${TARGETARCH} && \
    (if [ -f /usr/local/lib64/libssl.so.1.1 ]; then \
        echo "Found OpenSSL in /usr/local/lib64" && \
        cp /usr/local/lib64/libssl.so.1.1 /binaries/${TARGETARCH}/ && \
        cp /usr/local/lib64/libcrypto.so.1.1 /binaries/${TARGETARCH}/; \
    elif [ -f /usr/local/lib/libssl.so.1.1 ]; then \
        echo "Found OpenSSL in /usr/local/lib" && \
        cp /usr/local/lib/libssl.so.1.1 /binaries/${TARGETARCH}/ && \
        cp /usr/local/lib/libcrypto.so.1.1 /binaries/${TARGETARCH}/; \
    elif [ -f /usr/lib64/libssl.so.1.1 ]; then \
        echo "Found OpenSSL in /usr/lib64" && \
        cp /usr/lib64/libssl.so.1.1 /binaries/${TARGETARCH}/ && \
        cp /usr/lib64/libcrypto.so.1.1 /binaries/${TARGETARCH}/; \
    else \
        echo "WARNING: OpenSSL libraries not found in standard locations." && \
        find / -name "libssl.so.1.1" -o -name "libcrypto.so.1.1" 2>/dev/null | xargs -r cp -t /binaries/${TARGETARCH}/ || \
        echo "ERROR: Could not find OpenSSL libraries to copy."; \
    fi)

# Download and build the GameLift Server SDK
RUN mkdir SDK && cd SDK && \
    wget -q https://gamelift-server-sdk-release.s3.us-west-2.amazonaws.com/cpp/GameLift-Cpp-ServerSDK-5.2.0.zip && \
    unzip -q GameLift-Cpp-ServerSDK-5.2.0.zip && \
    mkdir cmake-build && \
    # Configure CMake with architecture-specific flags
    if [ "$(uname -m)" = "aarch64" ] || [ "$TARGETARCH" = "arm64" ]; then \
      echo "Configuring GameLift SDK for ARM64..." && \
      # Architecture-specific flags are intentionally omitted here because:
      # 1. CMake automatically detects the architecture from the environment
      # 2. Docker buildx with platform flags already handles the architecture targeting
      # 3. Adding explicit arch flags in emulation can conflict with Docker's emulation layer
      # 4. The GameLift SDK's CMake is already designed to handle cross-compilation
      cmake -G "Unix Makefiles" -DBUILD_FOR_UNREAL=1 -DCMAKE_BUILD_TYPE=Release -S . -B ./cmake-build > /dev/null; \
    else \
      echo "Configuring GameLift SDK for AMD64..." && \
      # Same CMake command for both architectures - relying on automatic detection
      # rather than explicit architecture flags for better cross-platform compatibility
      cmake -G "Unix Makefiles" -DBUILD_FOR_UNREAL=1 -DCMAKE_BUILD_TYPE=Release -S . -B ./cmake-build > /dev/null; \
    fi && \
    # Build the SDK
    echo "Building GameLift Server SDK..." && \
    cmake --build cmake-build --target all -j$(nproc) > /dev/null && \
    cd ./cmake-build/prefix/ && \
    cp -r ./lib/* /binaries/${TARGETARCH}/ && \
    mkdir -p /binaries/${TARGETARCH}/include && \
    cp -r ./include/* /binaries/${TARGETARCH}/include/ && \
    # Clean up to save space
    cd ../../.. && \
    rm -rf SDK

# Show what we've collected in the binaries directory
RUN echo "Build artifacts:" && ls -la /binaries/${TARGETARCH}/

# Copy the binaries only to a clean setup
FROM scratch AS server
  ARG TARGETARCH=amd64
  COPY --from=build-server /binaries/${TARGETARCH}/ /
  ENTRYPOINT [ "/GameLiftSampleServer" ]

