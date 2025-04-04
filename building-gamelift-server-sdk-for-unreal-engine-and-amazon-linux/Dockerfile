FROM --platform=$BUILDPLATFORM amazonlinux:2023 as build-server

# Set architecture as build arg with default to amd64
ARG TARGETARCH=amd64
ARG BUILDPLATFORM
# Set OpenSSL version as build arg with default to 1.1.1n (compatible with UE 5.1, 5.2)
ARG OPENSSL_VERSION=1.1.1n

# Install only the essential dependencies with minimal extras
RUN yum install -y --setopt=install_weak_deps=False \
    gcc-c++ cmake3 git wget openssl-devel tar perl sudo \
    && yum clean all \
    && rm -rf /var/cache/yum

# Format OpenSSL version string for download URL
RUN echo "Configuring OpenSSL version ${OPENSSL_VERSION}" && \
    OPENSSL_FORMAT_VERSION=$(echo "${OPENSSL_VERSION}" | tr '.' '_')

# Install correct OpenSSL version based on build arg
RUN wget https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz && \
    tar -xzf OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz && \
    cd openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/ && \
    # Configure with arch-specific optimization flags
    if [ "$TARGETARCH" = "arm64" ]; then \
      # ARM64-specific configuration
      ./config -march=armv8-a; \
    else \
      # AMD64-specific configuration
      ./config -m64; \
    fi && \
    make -j$(nproc) && \
    make install && \
    cd .. && \
    rm -rf OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_').tar.gz openssl-OpenSSL_$(echo "${OPENSSL_VERSION}" | tr '.' '_')/

# Make sure OpenSSL is correctly installed
RUN export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64 && \
    openssl version

# Copy the Open SSL files to binaries folder
RUN mkdir -p /binaries/${TARGETARCH} && \
    cp /usr/local/lib/libssl.so.1.1 /binaries/${TARGETARCH}/ && \
    cp /usr/local/lib/libcrypto.so.1.1 /binaries/${TARGETARCH}/

# Download and build the GameLift Server SDK
RUN mkdir SDK && cd SDK && \
    wget https://gamelift-server-sdk-release.s3.us-west-2.amazonaws.com/cpp/GameLift-Cpp-ServerSDK-5.2.0.zip && \
    unzip GameLift-Cpp-ServerSDK-5.2.0.zip && \
    mkdir cmake-build && \
    # Configure CMake with architecture-specific flags
    if [ "$TARGETARCH" = "arm64" ]; then \
      echo "Configuring for ARM64..." && \
      cmake -G "Unix Makefiles" -DBUILD_FOR_UNREAL=1 -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_FLAGS="-march=armv8-a" -S . -B ./cmake-build; \
    else \
      echo "Configuring for AMD64..." && \
      cmake -G "Unix Makefiles" -DBUILD_FOR_UNREAL=1 -DCMAKE_BUILD_TYPE=Release -S . -B ./cmake-build; \
    fi && \
    # Build the SDK
    cmake --build cmake-build --target all && \
    cd ./cmake-build/prefix/ && \
    cp -r ./lib/* /binaries/${TARGETARCH}/ && \
    mkdir -p /binaries/${TARGETARCH}/include && \
    cp -r ./include/* /binaries/${TARGETARCH}/include/ && \
    # Clean up to save space
    cd ../../.. && \
    rm -rf SDK

# Copy the binaries only to a clean setup
FROM scratch AS server
  ARG TARGETARCH=amd64
  COPY --from=build-server /binaries/${TARGETARCH}/ /
  ENTRYPOINT [ "/GameLiftSampleServer" ]

